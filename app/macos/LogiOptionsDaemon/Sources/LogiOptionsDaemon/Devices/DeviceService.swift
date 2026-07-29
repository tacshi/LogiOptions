import Foundation

protocol DeviceAdapter {
    var permitsVirtualOpen: Bool { get }
    func scan() -> [HidppEndpoint]
    func open(_ endpoint: HidppEndpoint) -> HidppDevice?
}

struct ProductionDeviceAdapter: DeviceAdapter {
    let permitsVirtualOpen = false
    func scan() -> [HidppEndpoint] {
        HidppDiscovery.scan()
    }

    func open(_ endpoint: HidppEndpoint) -> HidppDevice? {
        HidppDiscovery.open(endpoint: endpoint)
    }
}

/// Deep device module. Callers select and observe logical devices without
/// knowing receiver slots, IOHID interfaces, registry matching, or HID++ probes.
final class DeviceService {
    private let adapter: DeviceAdapter
    private(set) var endpoints: [HidppEndpoint] = []
    private(set) var selectedEndpoint: HidppEndpoint?
    private(set) var selectedDevice: HidppDevice?
    private(set) var selectedFeatures: DeviceFeatures?

    var onChange: (() -> Void)?

    init(adapter: DeviceAdapter = ProductionDeviceAdapter()) {
        self.adapter = adapter
    }

    @discardableResult
    func rescan(preferredDeviceId: String?) -> Bool {
        let old = endpoints
        let previousSelectedId = selectedEndpoint?.descriptor.id
        // One IOHID interface owns one report callback. Release the active
        // handle before probing receiver slots, then reopen the chosen device.
        selectedFeatures = nil
        selectedDevice = nil
        var seenDeviceIds = Set<String>()
        endpoints = adapter.scan().filter {
            seenDeviceIds.insert($0.descriptor.id).inserted
        }
        let requestedId = preferredDeviceId ?? previousSelectedId
        let desiredId: String?
        if let requestedId {
            // Preserve an explicit selection while it is disconnected. Never
            // silently jump to another connected Logitech product.
            desiredId = endpoints.contains {
                $0.descriptor.id == requestedId
            } ? requestedId : nil
        } else {
            desiredId = endpoints.first?.descriptor.id
        }
        let changed = old != endpoints
        _ = select(deviceId: desiredId)
        return changed
    }

    @discardableResult
    func select(deviceId: String?) -> Bool {
        guard let deviceId,
              let endpoint = endpoints.first(where: { $0.descriptor.id == deviceId }) else {
            selectedEndpoint = nil
            selectedDevice = nil
            selectedFeatures = nil
            onChange?()
            return false
        }
        let device = adapter.open(endpoint)
        guard device != nil || adapter.permitsVirtualOpen else {
            selectedEndpoint = nil
            selectedDevice = nil
            selectedFeatures = nil
            onChange?()
            return false
        }
        selectedEndpoint = endpoint
        selectedDevice = device
        selectedFeatures = device.map(DeviceFeatures.init(device:))
        onChange?()
        return true
    }

    var selectedDescriptor: DeviceDescriptor? {
        selectedEndpoint?.descriptor
    }

    var descriptors: [DeviceDescriptor] {
        endpoints.map(\.descriptor).sorted { $0.name < $1.name }
    }
}

final class FakeDeviceAdapter: DeviceAdapter {
    let permitsVirtualOpen = true
    var endpoints: [HidppEndpoint]

    init(endpoints: [HidppEndpoint]) {
        self.endpoints = endpoints
    }

    func scan() -> [HidppEndpoint] {
        endpoints
    }

    func open(_ endpoint: HidppEndpoint) -> HidppDevice? {
        nil
    }
}
