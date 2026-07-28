import Foundation

// MARK: - Config model (JSON, shared shape with Flutter)

struct AppIdentity: Codable, Equatable {
    var displayName: String
    var path: String?
}

struct DeviceSettings: Codable, Equatable {
    var hapticEnabled = true
    var hapticLevel = 60
    var hapticPowerSave = false
    var forceThreshold: Int?
}

struct DeviceConfiguration: Codable, Equatable {
    var modelId: String
    var global: ProfileSettings
    var apps: [String: ProfileSettings]
    var applicationMetadata: [String: AppIdentity]
    var settings: DeviceSettings

    init(
        modelId: String,
        global: ProfileSettings,
        apps: [String: ProfileSettings] = [:],
        applicationMetadata: [String: AppIdentity] = [:],
        settings: DeviceSettings = DeviceSettings()
    ) {
        self.modelId = modelId
        self.global = global
        self.apps = apps
        self.applicationMetadata = applicationMetadata
        self.settings = settings
    }
}

struct AppConfig: Codable, Equatable {
    static let legacyDeviceId = "legacy:mx-master-3s"

    var version: Int
    var revision: Int
    var selectedDeviceId: String?
    var devices: [String: DeviceConfiguration]
    var recentDevices: [String: DeviceDescriptor]

    static let `default` = AppConfig(
        version: 3,
        revision: 0,
        selectedDeviceId: legacyDeviceId,
        devices: [
            legacyDeviceId: DeviceConfiguration(
                modelId: "2b034",
                global: .defaultGlobal
            ),
        ],
        recentDevices: [:]
    )

    private enum CodingKeys: String, CodingKey {
        case version, revision, selectedDeviceId, devices, recentDevices
        case global, apps
    }

    init(
        version: Int = 3,
        revision: Int = 0,
        selectedDeviceId: String? = nil,
        devices: [String: DeviceConfiguration] = [:],
        recentDevices: [String: DeviceDescriptor] = [:]
    ) {
        self.version = version
        self.revision = revision
        self.selectedDeviceId = selectedDeviceId
        self.devices = devices
        self.recentDevices = recentDevices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        if decodedVersion >= 3 {
            version = 3
            revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
            selectedDeviceId = try container.decodeIfPresent(String.self, forKey: .selectedDeviceId)
            devices = try container.decodeIfPresent(
                [String: DeviceConfiguration].self,
                forKey: .devices
            ) ?? [:]
            recentDevices = try container.decodeIfPresent(
                [String: DeviceDescriptor].self,
                forKey: .recentDevices
            ) ?? [:]
            if selectedDeviceId == nil {
                selectedDeviceId = devices.keys.sorted().first
            }
            return
        }

        let oldGlobal = try container.decodeIfPresent(
            ProfileSettings.self,
            forKey: .global
        ) ?? .defaultGlobal
        let oldApps = try container.decodeIfPresent(
            [String: ProfileSettings].self,
            forKey: .apps
        ) ?? [:]
        version = 3
        revision = 0
        selectedDeviceId = Self.legacyDeviceId
        devices = [
            Self.legacyDeviceId: DeviceConfiguration(
                modelId: "2b034",
                global: oldGlobal,
                apps: oldApps
            ),
        ]
        recentDevices = [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(3, forKey: .version)
        try container.encode(revision, forKey: .revision)
        try container.encodeIfPresent(selectedDeviceId, forKey: .selectedDeviceId)
        try container.encode(devices, forKey: .devices)
        try container.encode(recentDevices, forKey: .recentDevices)
    }

    var global: ProfileSettings {
        get {
            guard let id = selectedDeviceId else { return .defaultGlobal }
            return devices[id]?.global ?? .defaultGlobal
        }
        set {
            let id = selectedDeviceId ?? Self.legacyDeviceId
            var configuration = devices[id] ?? DeviceConfiguration(
                modelId: "unknown",
                global: .defaultGlobal
            )
            configuration.global = newValue
            devices[id] = configuration
            selectedDeviceId = id
        }
    }

    var apps: [String: ProfileSettings] {
        get {
            guard let id = selectedDeviceId else { return [:] }
            return devices[id]?.apps ?? [:]
        }
        set {
            let id = selectedDeviceId ?? Self.legacyDeviceId
            var configuration = devices[id] ?? DeviceConfiguration(
                modelId: "unknown",
                global: .defaultGlobal
            )
            configuration.apps = newValue
            devices[id] = configuration
            selectedDeviceId = id
        }
    }

    mutating func ensureDevice(_ descriptor: DeviceDescriptor) {
        if devices[descriptor.id] == nil {
            if descriptor.modelId.lowercased().contains("b034"),
               let legacy = devices.removeValue(forKey: Self.legacyDeviceId) {
                var migrated = legacy
                migrated.modelId = descriptor.modelId
                devices[descriptor.id] = migrated
            } else {
                devices[descriptor.id] = DeviceConfiguration(
                    modelId: descriptor.modelId,
                    global: .defaultGlobal(for: descriptor)
                )
            }
        }
        if var existing = devices[descriptor.id] {
            // Stable identity wins over a previous catalog/parser mistake.
            // Keep all assignments while correcting the product model.
            existing.modelId = descriptor.modelId
            let defaults = ProfileSettings.defaultGlobal(for: descriptor)
            for (cid, action) in defaults.buttons where existing.global.buttons[cid] == nil {
                existing.global.buttons[cid] = action
            }
            devices[descriptor.id] = existing
        }
        recentDevices[descriptor.id] = descriptor
        if selectedDeviceId == nil || selectedDeviceId == Self.legacyDeviceId {
            selectedDeviceId = descriptor.id
        }
    }

    mutating func bumpRevision() {
        revision += 1
    }

    mutating func pruneUnsupportedDevices() {
        let unsupportedIds = devices.compactMap { id, configuration in
            DeviceRegistry.supports(modelId: configuration.modelId) ? nil : id
        }
        guard !unsupportedIds.isEmpty else { return }
        for id in unsupportedIds {
            devices.removeValue(forKey: id)
            recentDevices.removeValue(forKey: id)
        }
        if let selectedDeviceId, unsupportedIds.contains(selectedDeviceId) {
            self.selectedDeviceId = recentDevices.values
                .filter { DeviceRegistry.supports(modelId: $0.modelId) }
                .sorted { $0.name < $1.name }
                .first?
                .id
        }
    }
}

struct ProfileSettings: Codable, Equatable {
    var dpi: Int?
    var smartShiftEnabled: Bool?
    var smartShiftThreshold: Int?
    var hiresWheel: Bool?
    var invertWheel: Bool?
    /// 0…1 host scroll speed (Options+ “Scrolling speed”). Default ~0.35.
    var scrollSpeed: Double?
    var thumbDivert: Bool?
    var thumbInvert: Bool?
    /// 0…1 thumb wheel speed (Options+ default ~0.30).
    var thumbSpeed: Double?
    /// "scroll" or "actions".
    var thumbMode: String?
    var thumbLeftAction: SimpleAction?
    var thumbRightAction: SimpleAction?
    /// Keys are hex CIDs like "0x52", "0xC3"
    var buttons: [String: ActionSpec] = [:]

    static var defaultGlobal: ProfileSettings {
        var p = ProfileSettings()
        p.dpi = 1000
        p.smartShiftEnabled = true
        p.smartShiftThreshold = 10
        p.hiresWheel = true
        p.invertWheel = false
        // Host scroll scale: 1.0 = 100%, up to 2.0 = 200%.
        p.scrollSpeed = 1.0
        p.thumbDivert = true
        p.thumbInvert = false
        p.thumbSpeed = 1.0
        p.buttons = [
            "0x52": .mouse(button: "middle"),
            "0x53": .mouse(button: "back"),
            "0x56": .mouse(button: "forward"),
            "0xC3": .gesture(
                click: SimpleAction.system(id: "mission_control"),
                up: SimpleAction.system(id: "mission_control"),
                down: SimpleAction.system(id: "app_expose"),
                // Prefer system desktop actions (System Events), not Ctrl+Arrow
                // keystrokes that Flutter's NavigationBar can steal when focused.
                left: SimpleAction.system(id: "previous_desktop"),
                right: SimpleAction.system(id: "next_desktop")
            ),
            "0xC4": .smartShiftToggle,
        ]
        return p
    }

    static func defaultGlobal(for descriptor: DeviceDescriptor) -> ProfileSettings {
        var profile = ProfileSettings()
        profile.dpi = descriptor.capabilities.dpi.map {
            min(
                $0.maximum,
                max($0.minimum, descriptor.kind == .trackball ? 400 : 1_000)
            )
        }
        if descriptor.capabilities.smartShift {
            profile.smartShiftEnabled = true
            profile.smartShiftThreshold = 10
        }
        if descriptor.capabilities.hiResWheel {
            profile.hiresWheel = true
            profile.invertWheel = false
            profile.scrollSpeed = 1.0
        }
        if descriptor.capabilities.thumbWheel {
            profile.thumbDivert = true
            profile.thumbInvert = false
            profile.thumbSpeed = 1.0
            profile.thumbMode = "scroll"
        }
        for control in descriptor.controls {
            let action: ActionSpec
            switch control.cid {
            case 0x50: action = .mouse(button: "left")
            case 0x51: action = .mouse(button: "right")
            case 0x52: action = .mouse(button: "middle")
            case 0x53, 0x54, 0x55: action = .mouse(button: "back")
            case 0x56, 0x57, 0x58: action = .mouse(button: "forward")
            case 0xC3:
                action = .gesture(
                    click: .system(id: "mission_control"),
                    up: .system(id: "mission_control"),
                    down: .system(id: "app_expose"),
                    left: .system(id: "previous_desktop"),
                    right: .system(id: "next_desktop")
                )
            case 0xC4: action = .smartShiftToggle
            case 0x1A0: action = .none
            default: action = .none
            }
            profile.buttons[control.id] = action
        }
        return profile
    }

    func merged(over base: ProfileSettings) -> ProfileSettings {
        var out = base
        if let dpi { out.dpi = dpi }
        if let smartShiftEnabled { out.smartShiftEnabled = smartShiftEnabled }
        if let smartShiftThreshold { out.smartShiftThreshold = smartShiftThreshold }
        if let hiresWheel { out.hiresWheel = hiresWheel }
        if let invertWheel { out.invertWheel = invertWheel }
        if let scrollSpeed { out.scrollSpeed = scrollSpeed }
        if let thumbDivert { out.thumbDivert = thumbDivert }
        if let thumbInvert { out.thumbInvert = thumbInvert }
        if let thumbSpeed { out.thumbSpeed = thumbSpeed }
        if let thumbMode { out.thumbMode = thumbMode }
        if let thumbLeftAction { out.thumbLeftAction = thumbLeftAction }
        if let thumbRightAction { out.thumbRightAction = thumbRightAction }
        for (k, v) in buttons {
            out.buttons[k] = v
        }
        return out
    }
}

/// Leaf / nested action. Gesture directions are non-recursive `SimpleAction`
/// values so the Swift compiler does not crash on recursive enum IRGen.
enum ActionSpec: Codable, Equatable {
    case none
    case mouse(button: String)
    case keystroke(keys: [String])
    case system(id: String)
    case media(id: String)
    case open(kind: String, value: String)
    case smartShiftToggle
    case gesture(GestureMap)

    private enum CodingKeys: String, CodingKey {
        case type, button, keys, id, kind, value, click, up, down, left, right
    }

    private enum Kind: String, Codable {
        case none, mouse, keystroke, system, media, open, smartshift_toggle, gesture
    }

    static func gesture(
        click: SimpleAction,
        up: SimpleAction,
        down: SimpleAction,
        left: SimpleAction,
        right: SimpleAction
    ) -> ActionSpec {
        .gesture(GestureMap(click: click, up: up, down: down, left: left, right: right))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(Kind.self, forKey: .type)
        switch type {
        case .none:
            self = .none
        case .mouse:
            self = .mouse(button: try c.decode(String.self, forKey: .button))
        case .keystroke:
            self = .keystroke(keys: try c.decode([String].self, forKey: .keys))
        case .system:
            self = .system(id: try c.decode(String.self, forKey: .id))
        case .media:
            self = .media(id: try c.decode(String.self, forKey: .id))
        case .open:
            self = .open(
                kind: try c.decode(String.self, forKey: .kind),
                value: try c.decode(String.self, forKey: .value)
            )
        case .smartshift_toggle:
            self = .smartShiftToggle
        case .gesture:
            self = .gesture(
                GestureMap(
                    click: try c.decode(SimpleAction.self, forKey: .click),
                    up: try c.decode(SimpleAction.self, forKey: .up),
                    down: try c.decode(SimpleAction.self, forKey: .down),
                    left: try c.decode(SimpleAction.self, forKey: .left),
                    right: try c.decode(SimpleAction.self, forKey: .right)
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode(Kind.none, forKey: .type)
        case .mouse(let button):
            try c.encode(Kind.mouse, forKey: .type)
            try c.encode(button, forKey: .button)
        case .keystroke(let keys):
            try c.encode(Kind.keystroke, forKey: .type)
            try c.encode(keys, forKey: .keys)
        case .system(let id):
            try c.encode(Kind.system, forKey: .type)
            try c.encode(id, forKey: .id)
        case .media(let id):
            try c.encode(Kind.media, forKey: .type)
            try c.encode(id, forKey: .id)
        case .open(let kind, let value):
            try c.encode(Kind.open, forKey: .type)
            try c.encode(kind, forKey: .kind)
            try c.encode(value, forKey: .value)
        case .smartShiftToggle:
            try c.encode(Kind.smartshift_toggle, forKey: .type)
        case .gesture(let map):
            try c.encode(Kind.gesture, forKey: .type)
            try c.encode(map.click, forKey: .click)
            try c.encode(map.up, forKey: .up)
            try c.encode(map.down, forKey: .down)
            try c.encode(map.left, forKey: .left)
            try c.encode(map.right, forKey: .right)
        }
    }

    func asSimple() -> SimpleAction {
        switch self {
        case .none: return .none
        case .mouse(let b): return .mouse(button: b)
        case .keystroke(let k): return .keystroke(keys: k)
        case .system(let id): return .system(id: id)
        case .media(let id): return .media(id: id)
        case .open(let kind, let value): return .open(kind: kind, value: value)
        case .smartShiftToggle: return .smartShiftToggle
        case .gesture: return .none
        }
    }
}

struct GestureMap: Codable, Equatable {
    var click: SimpleAction
    var up: SimpleAction
    var down: SimpleAction
    var left: SimpleAction
    var right: SimpleAction
}

/// Non-recursive action used inside gesture directions.
enum SimpleAction: Codable, Equatable {
    case none
    case mouse(button: String)
    case keystroke(keys: [String])
    case system(id: String)
    case media(id: String)
    case open(kind: String, value: String)
    case smartShiftToggle

    private enum CodingKeys: String, CodingKey {
        case type, button, keys, id, kind, value
    }

    private enum Kind: String, Codable {
        case none, mouse, keystroke, system, media, open, smartshift_toggle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(Kind.self, forKey: .type)
        switch type {
        case .none: self = .none
        case .mouse: self = .mouse(button: try c.decode(String.self, forKey: .button))
        case .keystroke: self = .keystroke(keys: try c.decode([String].self, forKey: .keys))
        case .system: self = .system(id: try c.decode(String.self, forKey: .id))
        case .media: self = .media(id: try c.decode(String.self, forKey: .id))
        case .open:
            self = .open(
                kind: try c.decode(String.self, forKey: .kind),
                value: try c.decode(String.self, forKey: .value)
            )
        case .smartshift_toggle: self = .smartShiftToggle
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode(Kind.none, forKey: .type)
        case .mouse(let button):
            try c.encode(Kind.mouse, forKey: .type)
            try c.encode(button, forKey: .button)
        case .keystroke(let keys):
            try c.encode(Kind.keystroke, forKey: .type)
            try c.encode(keys, forKey: .keys)
        case .system(let id):
            try c.encode(Kind.system, forKey: .type)
            try c.encode(id, forKey: .id)
        case .media(let id):
            try c.encode(Kind.media, forKey: .type)
            try c.encode(id, forKey: .id)
        case .open(let kind, let value):
            try c.encode(Kind.open, forKey: .type)
            try c.encode(kind, forKey: .kind)
            try c.encode(value, forKey: .value)
        case .smartShiftToggle:
            try c.encode(Kind.smartshift_toggle, forKey: .type)
        }
    }

    func toActionSpec() -> ActionSpec {
        switch self {
        case .none: return .none
        case .mouse(let b): return .mouse(button: b)
        case .keystroke(let k): return .keystroke(keys: k)
        case .system(let id): return .system(id: id)
        case .media(let id): return .media(id: id)
        case .open(let kind, let value): return .open(kind: kind, value: value)
        case .smartShiftToggle: return .smartShiftToggle
        }
    }
}

enum ConfigStore {
    static func load() -> AppConfig {
        let url = SocketPaths.configFile
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            let cfg = AppConfig.default
            save(cfg)
            return cfg
        }
        return cfg
    }

    static func save(_ config: AppConfig) {
        try? FileManager.default.createDirectory(at: SocketPaths.configDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) {
            try? data.write(to: SocketPaths.configFile, options: .atomic)
        }
    }
}

extension ProfileSettings {
    func action(forCid cid: UInt16) -> ActionSpec? {
        let candidates = [
            String(format: "0x%X", cid),
            String(format: "0x%x", cid),
            String(format: "0x%02X", cid),
            String(format: "0x%02x", cid),
            String(format: "0x%04X", cid),
            String(cid, radix: 16),
        ]
        for k in candidates {
            if let a = buttons[k] { return a }
        }
        // Case-insensitive scan
        let lower = String(format: "0x%x", cid)
        for (k, v) in buttons where k.lowercased() == lower {
            return v
        }
        return nil
    }
}
