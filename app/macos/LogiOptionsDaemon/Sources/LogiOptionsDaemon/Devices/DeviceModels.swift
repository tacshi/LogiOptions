import Foundation

enum PointingDeviceKind: String, Codable, Equatable {
    case mouse
    case trackball
}

enum DeviceVerification: String, Codable, Equatable {
    case verified
    case compatible
}

struct DpiRange: Codable, Equatable {
    var minimum: Int
    var maximum: Int
    var step: Int
}

struct DeviceCapabilities: Codable, Equatable {
    var battery: Bool
    var dpi: DpiRange?
    var hiResWheel: Bool
    var smartShift: Bool
    var thumbWheel: Bool
    var haptics: Bool
    var forceSensing: Bool

    static let minimal = DeviceCapabilities(
        battery: false,
        dpi: nil,
        hiResWheel: false,
        smartShift: false,
        thumbWheel: false,
        haptics: false,
        forceSensing: false
    )

    func intersecting(_ detected: DeviceCapabilities) -> DeviceCapabilities {
        DeviceCapabilities(
            battery: battery && detected.battery,
            dpi: detected.dpi ?? dpi,
            hiResWheel: hiResWheel && detected.hiResWheel,
            smartShift: smartShift && detected.smartShift,
            thumbWheel: thumbWheel && detected.thumbWheel,
            haptics: haptics && detected.haptics,
            forceSensing: forceSensing && detected.forceSensing
        )
    }
}

struct DeviceControl: Codable, Equatable, Identifiable {
    var cid: UInt16
    var label: String
    /// Normalized coordinates (0...1) for the matching editor artwork.
    var x: Double
    var y: Double

    var id: String { String(format: "0x%X", cid) }
}

struct DeviceDescriptor: Codable, Equatable, Identifiable {
    var id: String
    var modelId: String
    var name: String
    var kind: PointingDeviceKind
    var transport: String
    var connected: Bool
    var verification: DeviceVerification
    var capabilities: DeviceCapabilities
    var controls: [DeviceControl]
    var artworkKey: String
}

struct DeviceLiveState: Codable, Equatable {
    var batteryPercent: Int?
    var charging: Bool
    var dpi: Int?
    var smartShiftEnabled: Bool?
    var smartShiftThreshold: Int?
    var hiResWheel: Bool?
    var invertWheel: Bool?
    var scrollSpeed: Double?
    var thumbDiverted: Bool?
    var thumbInvert: Bool?
    var thumbSpeed: Double?

    static let empty = DeviceLiveState(
        batteryPercent: nil,
        charging: false,
        dpi: nil,
        smartShiftEnabled: nil,
        smartShiftThreshold: nil,
        hiResWheel: nil,
        invertWheel: nil,
        scrollSpeed: nil,
        thumbDiverted: nil,
        thumbInvert: nil,
        thumbSpeed: nil
    )
}

struct DeviceSnapshot: Codable, Equatable {
    var devices: [DeviceDescriptor]
    var selectedDeviceId: String?
    var selectedState: DeviceLiveState
}

struct DeviceCatalogEntry: Equatable {
    var modelId: String
    var name: String
    var kind: PointingDeviceKind
    var capabilities: DeviceCapabilities
    var controls: [DeviceControl]
    var artworkKey: String
}
