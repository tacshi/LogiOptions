import Foundation

enum Hidpp {
    static let logitechVendorId = 0x046D
    static let shortReportId: UInt8 = 0x10
    static let longReportId: UInt8 = 0x11
    static let directDeviceIndex: UInt8 = 0xFF

    /// Bolt / Unifying style receivers.
    static let receiverProductIds: Set<Int> = [
        0xC52B, 0xC532, 0xC534, 0xC539, 0xC53A,
        0xC545, 0xC547, 0xC548,
    ]

    enum Feature: UInt16 {
        case root = 0x0000
        case featureSet = 0x0001
        case batteryStatus = 0x1000
        case unifiedBattery = 0x1004
        case reprogControlsV4 = 0x1B04
        case changeHost = 0x1814
        case smartShift = 0x2110
        case smartShiftEnhanced = 0x2111
        case hiResWheel = 0x2121
        case thumbWheel = 0x2150
        case adjustableDpi = 0x2201
        case extendedAdjustableDpi = 0x2202
    }

    /// MX Master 3S control IDs (Special Keys / ReprogControls).
    enum Control: UInt16 {
        case middle = 0x0052
        case back = 0x0053
        case forward = 0x0056
        case gesture = 0x00C3
        case modeShift = 0x00C4
    }

    /// MappingFlag.DIVERTED | valid bit.
    static let divertFlags: UInt8 = 0x01 | 0x02
}

enum SocketPaths {
    /// Fixed path so UI and daemon always agree (TMPDIR can differ per process).
    static var socket: String { "/tmp/logioptions.sock" }

    static var configDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LogiOptions", isDirectory: true)
    }

    static var configFile: URL {
        configDir.appendingPathComponent("config.json")
    }
}
