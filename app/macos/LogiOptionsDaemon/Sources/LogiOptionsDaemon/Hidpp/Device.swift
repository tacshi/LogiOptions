import Foundation
import IOKit
import IOKit.hid

protocol HidppRequesting: AnyObject {
    var name: String { get }
    var isReceiver: Bool { get }
    var protocolVersion: Double { get }
    func featureRequest(featureIndex: UInt8, function: UInt8, params: [UInt8]) -> Data?
    func resolveFeature(_ id: Hidpp.Feature) -> (index: UInt8, version: UInt8)?
    func legacyReadRegister(_ register: UInt16, params: [UInt8]) -> Data?
}

extension HidppRequesting {
    func featureRequest(featureIndex: UInt8, function: UInt8) -> Data? {
        featureRequest(featureIndex: featureIndex, function: function, params: [])
    }

    func legacyReadRegister(_ register: UInt16) -> Data? {
        legacyReadRegister(register, params: [])
    }
}

/// Low-level HID++ 1.0/2.0 client over a single IOHIDDevice interface.
final class HidppDevice: HidppRequesting {
    let device: IOHIDDevice
    let name: String
    let productId: Int
    let transport: String
    let serialNumber: String?
    let locationId: Int
    var deviceIndex: UInt8
    private var softwareId: UInt8 = 0x8
    private let reportPtr: UnsafeMutablePointer<UInt8>
    private let reportCapacity = 64
    private var isOpen = false
    private var waitMatch: UInt16?
    private var waitResult: Data?
    private var lastHidpp10Error: UInt8?
    private let lock = NSLock()
    /// True while a HID++ wait is pumping the main run loop (blocks re-entrant polls).
    private(set) var isBusy = false
    private var featureCache: [UInt16: (index: UInt8, version: UInt8)] = [:]
    private(set) var protocolVersion: Double = 0

    /// Unmatched HID++ notifications (divert, wheel, etc.).
    var onNotification: ((UInt8 /* featureIndex */, UInt8 /* function */, Data /* params */) -> Void)?
    /// The underlying HID interface was physically removed.
    var onRemoval: (() -> Void)?

    var isReceiver: Bool {
        name.localizedCaseInsensitiveContains("receiver")
            || Hidpp.receiverProductIds.contains(productId)
    }

    init?(device: IOHIDDevice, runLoop: CFRunLoop = CFRunLoopGetMain()) {
        self.device = device
        self.name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "unknown"
        self.productId = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        self.transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? "?"
        self.serialNumber = IOHIDDeviceGetProperty(
            device,
            kIOHIDSerialNumberKey as CFString
        ) as? String
        self.locationId = (
            IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber
        )?.intValue ?? 0
        let receiver = name.localizedCaseInsensitiveContains("receiver")
            || Hidpp.receiverProductIds.contains(productId)
        self.deviceIndex = receiver ? 0x01 : Hidpp.directDeviceIndex
        self.reportPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: reportCapacity)
        reportPtr.initialize(repeating: 0, count: reportCapacity)

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            DaemonLog.warn(
                "Unable to open HID++ interface \(name) "
                    + String(format: "(0x%08x)", openResult)
            )
            return nil
        }
        isOpen = true

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            reportPtr,
            reportCapacity,
            { context, _, _, _, _, report, length in
                guard let context else { return }
                let me = Unmanaged<HidppDevice>.fromOpaque(context).takeUnretainedValue()
                let data = Data(bytes: report, count: Int(length))
                me.onReport(data)
            },
            ctx
        )
        IOHIDDeviceRegisterRemovalCallback(
            device,
            { context, _, _ in
                guard let context else { return }
                let me = Unmanaged<HidppDevice>.fromOpaque(context).takeUnretainedValue()
                me.onRemoval?()
            },
            ctx
        )
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        if isOpen {
            IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, 0)
        }
        reportPtr.deallocate()
    }

    private func onReport(_ data: Data) {
        guard data.count >= 4 else { return }
        let reportId = data[0]
        guard reportId == Hidpp.shortReportId || reportId == Hidpp.longReportId else { return }

        let featureOrSub = data[2]
        let fnAndSw = data[3]
        let reqId = (UInt16(featureOrSub) << 8) | UInt16(fnAndSw)

        lock.lock()
        if featureOrSub == 0x8F, data.count >= 6 {
            let failedRequest = (UInt16(data[3]) << 8) | UInt16(data[4])
            if let match = waitMatch,
               (match & 0xFFF0) == (failedRequest & 0xFFF0) {
                lastHidpp10Error = data[5]
                waitResult = nil
                waitMatch = nil
                lock.unlock()
                return
            }
        }
        if featureOrSub == 0xFF, data.count >= 6 {
            let failedRequest = (UInt16(data[3]) << 8) | UInt16(data[4])
            if let match = waitMatch,
               (match & 0xFFF0) == (failedRequest & 0xFFF0) {
                waitResult = nil
                waitMatch = nil
                lock.unlock()
                return
            }
        }
        if let match = waitMatch, (match & 0xFFF0) == (reqId & 0xFFF0) {
            waitResult = Data(data.dropFirst(4))
            waitMatch = nil
            lock.unlock()
            return
        }
        lock.unlock()

        // HID++ 2.0 notification: software id in low nibble is 0 for device events.
        let softwareId = fnAndSw & 0x0F
        if softwareId == 0 {
            let featureIndex = featureOrSub
            let function = fnAndSw & 0xF0
            let params = Data(data.dropFirst(4))
            onNotification?(featureIndex, function, params)
        }
    }

    private func nextSwId() -> UInt8 {
        softwareId = softwareId >= 0xF ? 0x8 : softwareId + 1
        return softwareId
    }

    @discardableResult
    func request(requestId: UInt16, params: [UInt8] = [], longMessage: Bool = true, timeout: TimeInterval = 0.8) -> Data? {
        // Nested calls already on main (e.g. resolveFeature → featureRequest).
        if Thread.isMainThread {
            return performRequest(requestId: requestId, params: params, longMessage: longMessage, timeout: timeout)
        }

        // Off-main (RPC queue): hop to main so IOHID input callbacks can fire.
        var result: Data?
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            result = self.performRequest(
                requestId: requestId,
                params: params,
                longMessage: longMessage,
                timeout: timeout
            )
            sem.signal()
        }
        let wait = timeout + 0.4
        if sem.wait(timeout: .now() + wait) == .timedOut {
            return nil
        }
        return result
    }

    private func performRequest(requestId: UInt16, params: [UInt8], longMessage: Bool, timeout: TimeInterval) -> Data? {
        precondition(Thread.isMainThread, "HID++ wait must run on main run loop")
        isBusy = true
        defer { isBusy = false }
        let sw = nextSwId()
        let rid = (requestId & 0xFFF0) | UInt16(sw)
        var body: [UInt8] = [deviceIndex, UInt8((rid >> 8) & 0xFF), UInt8(rid & 0xFF)] + params
        let reportId: UInt8 = (longMessage || body.count > 5) ? Hidpp.longReportId : Hidpp.shortReportId
        let target = reportId == Hidpp.longReportId ? 19 : 6
        while body.count < target { body.append(0) }
        if body.count > target { body = Array(body.prefix(target)) }

        let packetLen = 1 + body.count
        let packet = UnsafeMutablePointer<UInt8>.allocate(capacity: packetLen)
        defer { packet.deallocate() }
        packet[0] = reportId
        for i in 0..<body.count { packet[i + 1] = body[i] }

        lock.lock()
        waitMatch = rid
        waitResult = nil
        lastHidpp10Error = nil
        lock.unlock()

        var rc = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportId), packet, packetLen)
        if rc != kIOReturnSuccess {
            rc = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportId), packet + 1, packetLen - 1)
        }
        if rc != kIOReturnSuccess {
            lock.lock(); waitMatch = nil; lock.unlock()
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            lock.lock()
            let done = waitMatch == nil
            let result = waitResult
            lock.unlock()
            if done { return result }
        }
        lock.lock(); waitMatch = nil; lock.unlock()
        return nil
    }

    func featureRequest(featureIndex: UInt8, function: UInt8, params: [UInt8] = []) -> Data? {
        let requestId = (UInt16(featureIndex) << 8) | UInt16(function)
        return request(requestId: requestId, params: params, longMessage: true)
    }

    func resolveFeature(_ id: Hidpp.Feature) -> (index: UInt8, version: UInt8)? {
        guard protocolVersion >= 2 else { return nil }
        if let cached = featureCache[id.rawValue] { return cached }
        let params: [UInt8] = [UInt8((id.rawValue >> 8) & 0xFF), UInt8(id.rawValue & 0xFF)]
        guard let reply = featureRequest(featureIndex: 0x00, function: 0x00, params: params),
              reply.count >= 3, reply[0] != 0 else { return nil }
        let resolved = (reply[0], reply[2])
        featureCache[id.rawValue] = resolved
        return resolved
    }

    func clearFeatureCache() {
        featureCache.removeAll()
    }

    func probeProtocol() -> Double? {
        let marker = UInt8.random(in: 1 ... 254)
        let reply = request(
            requestId: 0x0010,
            params: [0x00, 0x00, marker],
            longMessage: false
        )
        if let reply, reply.count >= 3, reply[2] == marker {
            protocolVersion = Double(reply[0]) + Double(reply[1]) / 10
            return protocolVersion
        }
        if lastHidpp10Error == 0x01 {
            protocolVersion = 1.0
            return protocolVersion
        }
        return nil
    }

    func legacyReadRegister(_ register: UInt16, params: [UInt8] = []) -> Data? {
        guard protocolVersion > 0, protocolVersion < 2 else { return nil }
        return request(
            requestId: 0x8100 | (register & 0x02FF),
            params: params,
            longMessage: register > 0xFF
        )
    }

    func receiverPairingIdentity(slot: UInt8) -> (modelId: String?, serial: String?) {
        guard isReceiver else { return (nil, serialNumber) }
        let previousIndex = deviceIndex
        deviceIndex = Hidpp.directDeviceIndex
        defer { deviceIndex = previousIndex }

        let bolt = [0xC545, 0xC548].contains(productId)
        let subregister = bolt ? 0x50 + slot : 0x20 + slot - 1
        guard let reply = request(
            requestId: 0x83B5,
            params: [subregister],
            longMessage: true
        ), reply.count >= 5 else {
            return (nil, nil)
        }
        let wpid: String
        if bolt {
            wpid = String(format: "%02x%02x", reply[3], reply[2])
        } else {
            wpid = String(format: "%02x%02x", reply[3], reply[4])
        }
        let modelId = DeviceRegistry.entries.first {
            $0.modelId.lowercased().hasSuffix(wpid)
        }?.modelId
        let serial: String?
        if bolt, reply.count >= 8 {
            serial = reply[4 ..< 8].map { String(format: "%02x", $0) }.joined()
        } else {
            serial = nil
        }
        return (modelId, serial)
    }

    var interfaceKey: String {
        let serial = serialNumber?.lowercased() ?? "none"
        return String(format: "%04x-%08x-%@-%@", productId, locationId, transport.lowercased(), serial)
    }
}

struct HidppEndpoint: Equatable {
    var interfaceKey: String
    var deviceIndex: UInt8
    var descriptor: DeviceDescriptor
    var protocolVersion: Double = 2.0
}

enum HidppDiscovery {
    static func isHidppInterface(
        primaryUsagePage: Int,
        usagePairPages: [Int]
    ) -> Bool {
        primaryUsagePage >= 0xFF00
            || usagePairPages.contains { $0 >= 0xFF00 }
    }

    /// Find Logitech vendor-page HID interfaces suitable for HID++.
    static func enumerateCandidates() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Hidpp.logitechVendorId] as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.filter { device in
            let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
            let usagePairs =
                IOHIDDeviceGetProperty(device, "DeviceUsagePairs" as CFString)
                as? [[String: Any]] ?? []
            let usagePairPages = usagePairs.compactMap {
                ($0["DeviceUsagePage"] as? NSNumber)?.intValue
            }
            return isHidppInterface(
                primaryUsagePage: usagePage,
                usagePairPages: usagePairPages
            )
        }
    }

    static func scan(runLoop: CFRunLoop = CFRunLoopGetMain()) -> [HidppEndpoint] {
        var endpoints: [HidppEndpoint] = []
        for candidate in enumerateCandidates() {
            let productId = (
                IOHIDDeviceGetProperty(
                    candidate,
                    kIOHIDProductIDKey as CFString
                ) as? NSNumber
            )?.intValue ?? 0
            let productName = (
                IOHIDDeviceGetProperty(
                    candidate,
                    kIOHIDProductKey as CFString
                ) as? String
            ) ?? "unknown"
            guard DeviceRegistry.shouldInspectHidProduct(
                productId: productId,
                name: productName
            ) else {
                continue
            }
            guard let client = HidppDevice(device: candidate, runLoop: runLoop) else { continue }
            let indices: [UInt8] = client.isReceiver
                ? Array(1...6).map { UInt8($0) }
                : [0xFF, 0x00, 0x01]
            for idx in indices {
                client.deviceIndex = idx
                client.clearFeatureCache()
                guard let protocolVersion = client.probeProtocol() else { continue }
                if protocolVersion >= 2,
                   client.resolveFeature(.featureSet) == nil {
                    continue
                }
                let pairing = client.receiverPairingIdentity(slot: idx)
                let features = DeviceFeatures(device: client)
                let identity = features.readIdentity()
                let name = features.readDeviceName() ?? client.name
                guard let catalog = DeviceRegistry.entry(
                    modelId: identity.modelId ?? pairing.modelId,
                    name: name,
                    productId: client.productId
                ) else {
                    DaemonLog.info("Ignoring non-Options+ device \(name)")
                    continue
                }
                let detected = protocolVersion >= 2
                    ? features.detectedCapabilities(fallbackDpi: catalog.capabilities.dpi)
                    : DeviceCapabilities(
                        battery: true,
                        dpi: nil,
                        hiResWheel: false,
                        smartShift: false,
                        thumbWheel: false,
                        haptics: false,
                        forceSensing: false
                    )
                let capabilities = protocolVersion < 2 || catalog.capabilities == .minimal
                    ? detected : catalog.capabilities.intersecting(detected)
                let probedControls = protocolVersion >= 2
                    ? features.readProgrammableControls() : []
                let catalogControlIds = Set(catalog.controls.map(\.cid))
                let controls = (probedControls ?? [])
                    .filter { catalogControlIds.contains($0) }
                    .enumerated().map { offset, cid in
                        if let known = catalog.controls.first(where: { $0.cid == cid }) {
                            return known
                        }
                        return DeviceControl(
                            cid: cid,
                            label: DeviceRegistry.controlLabel(for: cid),
                            x: 0.50,
                            y: min(0.85, 0.18 + Double(offset) * 0.10)
                        )
                    }
                let stableId: String
                if let unit = identity.unitId {
                    stableId = "unit:\(unit)"
                } else if let serial = pairing.serial, !serial.isEmpty {
                    stableId = "serial:\(serial.lowercased())"
                } else if let serial = client.serialNumber, !serial.isEmpty {
                    stableId = "serial:\(serial.lowercased()):\(idx)"
                } else {
                    stableId = "hid:\(client.interfaceKey):\(String(format: "%02x", idx))"
                }
                let transport = normalizedTransport(
                    client.transport,
                    productId: client.productId,
                    isReceiver: client.isReceiver
                )
                let descriptor = DeviceDescriptor(
                    id: stableId,
                    modelId: catalog.modelId,
                    name: catalog.name == "Compatible Logitech pointing device" ? name : catalog.name,
                    kind: catalog.kind,
                    transport: transport,
                    connected: true,
                    verification: DeviceRegistry.isVerified(modelId: catalog.modelId)
                        ? .verified
                        : .compatible,
                    capabilities: capabilities,
                    controls: controls,
                    artworkKey: DeviceRegistry.artworkKey(
                        modelId: catalog.modelId,
                        extendedModel: identity.extendedModel
                    )
                )
                if !endpoints.contains(where: { $0.descriptor.id == stableId }) {
                    endpoints.append(HidppEndpoint(
                        interfaceKey: client.interfaceKey,
                        deviceIndex: idx,
                        descriptor: descriptor,
                        protocolVersion: protocolVersion
                    ))
                }
            }
        }
        return endpoints.sorted { $0.descriptor.name < $1.descriptor.name }
    }

    static func open(
        endpoint: HidppEndpoint,
        runLoop: CFRunLoop = CFRunLoopGetMain()
    ) -> HidppDevice? {
        for candidate in enumerateCandidates() {
            let productId = (
                IOHIDDeviceGetProperty(
                    candidate,
                    kIOHIDProductIDKey as CFString
                ) as? NSNumber
            )?.intValue ?? 0
            let productName = (
                IOHIDDeviceGetProperty(
                    candidate,
                    kIOHIDProductKey as CFString
                ) as? String
            ) ?? "unknown"
            guard DeviceRegistry.shouldInspectHidProduct(
                productId: productId,
                name: productName
            ) else {
                continue
            }
            guard let client = HidppDevice(device: candidate, runLoop: runLoop) else { continue }
            guard client.interfaceKey == endpoint.interfaceKey else { continue }
            client.deviceIndex = endpoint.deviceIndex
            client.clearFeatureCache()
            guard let protocolVersion = client.probeProtocol() else { continue }
            let usable = protocolVersion < 2 || client.resolveFeature(.featureSet) != nil
            if usable {
                DaemonLog.info(
                    "HID++ \(String(format: "%.1f", protocolVersion)) "
                        + "\(endpoint.descriptor.name) index=0x"
                        + String(format: "%02X", endpoint.deviceIndex)
                        + " transport=\(client.transport)"
                )
                return client
            }
        }
        return nil
    }

    /// Compatibility helper used while callers migrate to DeviceService.
    static func openFirst(runLoop: CFRunLoop = CFRunLoopGetMain()) -> HidppDevice? {
        guard let first = scan(runLoop: runLoop).first else { return nil }
        return open(endpoint: first, runLoop: runLoop)
    }

    static func normalizedTransport(
        _ value: String,
        productId: Int,
        isReceiver: Bool
    ) -> String {
        let upper = value.uppercased()
        if upper.contains("BLUETOOTH") || upper.contains("BLE") { return "ble" }
        if isReceiver {
            if productId == 0xC548 { return "bolt" }
            return "receiver"
        }
        if upper.contains("USB") { return "usb" }
        return value.lowercased()
    }
}
