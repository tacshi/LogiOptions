import Foundation
import IOKit
import IOKit.hid

/// Low-level HID++ 2.0 client over a single IOHIDDevice interface.
final class HidppDevice {
    let device: IOHIDDevice
    let name: String
    let productId: Int
    let transport: String
    var deviceIndex: UInt8
    private var softwareId: UInt8 = 0x8
    private let reportPtr: UnsafeMutablePointer<UInt8>
    private let reportCapacity = 64
    private var waitMatch: UInt16?
    private var waitResult: Data?
    private let lock = NSLock()
    /// True while a HID++ wait is pumping the main run loop (blocks re-entrant polls).
    private(set) var isBusy = false
    private var featureCache: [UInt16: (index: UInt8, version: UInt8)] = [:]

    /// Unmatched HID++ notifications (divert, wheel, etc.).
    var onNotification: ((UInt8 /* featureIndex */, UInt8 /* function */, Data /* params */) -> Void)?

    var isReceiver: Bool {
        name.localizedCaseInsensitiveContains("receiver")
            || Hidpp.receiverProductIds.contains(productId)
    }

    init?(device: IOHIDDevice, runLoop: CFRunLoop = CFRunLoopGetMain()) {
        self.device = device
        self.name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "unknown"
        self.productId = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        self.transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? "?"
        let receiver = name.localizedCaseInsensitiveContains("receiver")
            || Hidpp.receiverProductIds.contains(productId)
        self.deviceIndex = receiver ? 0x01 : Hidpp.directDeviceIndex
        self.reportPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: reportCapacity)
        reportPtr.initialize(repeating: 0, count: reportCapacity)

        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            reportPtr.deallocate()
            return nil
        }

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
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, 0)
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
}

enum HidppDiscovery {
    /// Find Logitech vendor-page HID interfaces suitable for HID++.
    static func enumerateCandidates() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Hidpp.logitechVendorId] as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.filter { device in
            let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
            return usagePage >= 0xFF00
        }
    }

    /// Open first responsive HID++ device (receiver slot or BLE direct).
    static func openFirst(runLoop: CFRunLoop = CFRunLoopGetMain()) -> HidppDevice? {
        for candidate in enumerateCandidates() {
            guard let client = HidppDevice(device: candidate, runLoop: runLoop) else { continue }
            let indices: [UInt8] = client.isReceiver
                ? Array(1...6).map { UInt8($0) }
                : [0xFF, 0x00, 0x01]
            for idx in indices {
                client.deviceIndex = idx
                client.clearFeatureCache()
                if client.resolveFeature(.featureSet) != nil {
                    DaemonLog.info("HID++ device \(client.name) index=0x\(String(format: "%02X", idx)) transport=\(client.transport)")
                    return client
                }
            }
        }
        return nil
    }
}
