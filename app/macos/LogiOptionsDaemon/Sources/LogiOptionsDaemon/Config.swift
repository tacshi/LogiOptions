import Foundation

// MARK: - Config model (JSON, shared shape with Flutter)

struct AppConfig: Codable, Equatable {
    var version: Int = 1
    var global: ProfileSettings = .defaultGlobal
    var apps: [String: ProfileSettings] = [:]

    static let `default` = AppConfig()
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
    case smartShiftToggle
    case gesture(GestureMap)

    private enum CodingKeys: String, CodingKey {
        case type, button, keys, id, click, up, down, left, right
    }

    private enum Kind: String, Codable {
        case none, mouse, keystroke, system, media, smartshift_toggle, gesture
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
    case smartShiftToggle

    private enum CodingKeys: String, CodingKey {
        case type, button, keys, id
    }

    private enum Kind: String, Codable {
        case none, mouse, keystroke, system, media, smartshift_toggle
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
