import AppKit
import CoreGraphics
import Foundation

/// Executes host-side actions (requires Accessibility for some paths).
final class ActionEngine {
    weak var features: MxFeaturesBox?

    func execute(_ action: ActionSpec) {
        switch action {
        case .none:
            break
        case .mouse(let button):
            postMouseButton(button)
        case .keystroke(let keys):
            postKeystroke(keys)
        case .system(let id):
            postSystem(id)
        case .media(let id):
            postMedia(id)
        case .smartShiftToggle:
            _ = features?.features.toggleSmartShift()
        case .gesture:
            // Nested gesture specs are handled by GestureTracker
            break
        }
    }

    // MARK: - Mouse

    private func postMouseButton(_ name: String) {
        let loc = CGEvent(source: nil)?.location ?? .zero
        switch name.lowercased() {
        case "left":
            click(button: .left, at: loc)
        case "right":
            click(button: .right, at: loc)
        case "middle":
            click(button: .center, at: loc)
        case "back":
            // macOS: button 3 often back
            otherClick(buttonNumber: 3, at: loc)
        case "forward":
            otherClick(buttonNumber: 4, at: loc)
        default:
            DaemonLog.warn("Unknown mouse button \(name)")
        }
    }

    private func click(button: CGMouseButton, at loc: CGPoint) {
        let downType: CGEventType
        let upType: CGEventType
        switch button {
        case .left: downType = .leftMouseDown; upType = .leftMouseUp
        case .right: downType = .rightMouseDown; upType = .rightMouseUp
        case .center: downType = .otherMouseDown; upType = .otherMouseUp
        @unknown default: downType = .leftMouseDown; upType = .leftMouseUp
        }
        if let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: loc, mouseButton: button) {
            if button == .center {
                down.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            }
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: loc, mouseButton: button) {
            if button == .center {
                up.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            }
            up.post(tap: .cghidEventTap)
        }
    }

    private func otherClick(buttonNumber: Int64, at loc: CGPoint) {
        if let down = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: loc, mouseButton: .center) {
            down.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: loc, mouseButton: .center) {
            up.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Keystrokes

    private func postKeystroke(_ keys: [String]) {
        let normalized = keys.map { $0.lowercased() }

        // Space switching: bare arrow keys were reaching the focused app (Flutter
        // nav tabs). Use System Events so Control is applied at the session level.
        if isDesktopSwitch(normalized) {
            let next = normalized.contains("right")
            switchDesktop(next: next)
            return
        }

        var flags: CGEventFlags = []
        var modifierVKs: [CGKeyCode] = []
        var mainKey: CGKeyCode?

        for k in normalized {
            switch k {
            case "cmd", "command", "meta":
                flags.insert(.maskCommand)
                modifierVKs.append(0x37) // kVK_Command
            case "shift":
                flags.insert(.maskShift)
                modifierVKs.append(0x38) // kVK_Shift
            case "alt", "option":
                flags.insert(.maskAlternate)
                modifierVKs.append(0x3A) // kVK_Option
            case "ctrl", "control":
                flags.insert(.maskControl)
                modifierVKs.append(0x3B) // kVK_Control
            case "fn":
                flags.insert(.maskSecondaryFn)
            default:
                mainKey = Self.keyCode(for: k)
            }
        }

        guard let code = mainKey else {
            DaemonLog.warn("No key code in \(keys)")
            return
        }

        // combinedSessionState + explicit modifier press/release is more reliable
        // for system hotkeys than flags-only on the main key.
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0

        for vk in modifierVKs {
            if let e = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: true) {
                e.flags = flags
                e.post(tap: .cghidEventTap)
            }
        }

        if let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }

        for vk in modifierVKs.reversed() {
            if let e = CGEvent(keyboardEventSource: source, virtualKey: vk, keyDown: false) {
                e.flags = []
                e.post(tap: .cghidEventTap)
            }
        }

        DaemonLog.info("keystroke \(keys.joined(separator: "+"))")
    }

    private func isDesktopSwitch(_ keys: [String]) -> Bool {
        let hasCtrl = keys.contains("ctrl") || keys.contains("control")
        let hasArrow = keys.contains("left") || keys.contains("right")
        // Exactly control + one horizontal arrow (optionally nothing else).
        let others = keys.filter {
            $0 != "ctrl" && $0 != "control" && $0 != "left" && $0 != "right"
        }
        return hasCtrl && hasArrow && others.isEmpty
    }

    /// Switch macOS Spaces (Options+ does this via its privileged agent).
    ///
    /// CGEvent Ctrl+Arrow often lands in the focused app (our Flutter nav bar).
    /// System Events injects at the session level. Off main/HID thread.
    private func switchDesktop(next: Bool) {
        let keyCode = next ? 124 : 123
        let ax = Permissions.accessibilityTrusted()
        DaemonLog.info("switchDesktop next=\(next) ax=\(ax)")
        let script =
            "tell application \"System Events\" to key code \(keyCode) using control down"
        DispatchQueue.global(qos: .userInteractive).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            task.standardOutput = FileHandle.nullDevice
            let errPipe = Pipe()
            task.standardError = errPipe
            do {
                try task.run()
                task.waitUntilExit()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errText = String(data: errData, encoding: .utf8) ?? ""
                if task.terminationStatus == 0 {
                    DaemonLog.info("switchDesktop next=\(next) via System Events")
                } else {
                    DaemonLog.warn(
                        "switchDesktop osascript status=\(task.terminationStatus) err=\(errText) — CGEvent fallback"
                    )
                    DispatchQueue.main.async {
                        self.forceControlArrow(next: next)
                    }
                }
            } catch {
                DaemonLog.warn("switchDesktop failed: \(error)")
                DispatchQueue.main.async {
                    self.forceControlArrow(next: next)
                }
            }
        }
    }

    private func forceControlArrow(next: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        let arrow: CGKeyCode = next ? 124 : 123
        let ctrl: CGKeyCode = 0x3B
        let flags: CGEventFlags = .maskControl

        if let e = CGEvent(keyboardEventSource: source, virtualKey: ctrl, keyDown: true) {
            e.flags = flags
            e.post(tap: .cgSessionEventTap)
        }
        if let e = CGEvent(keyboardEventSource: source, virtualKey: arrow, keyDown: true) {
            e.flags = flags
            e.post(tap: .cgSessionEventTap)
        }
        if let e = CGEvent(keyboardEventSource: source, virtualKey: arrow, keyDown: false) {
            e.flags = flags
            e.post(tap: .cgSessionEventTap)
        }
        if let e = CGEvent(keyboardEventSource: source, virtualKey: ctrl, keyDown: false) {
            e.flags = []
            e.post(tap: .cgSessionEventTap)
        }
        DaemonLog.info("forceControlArrow next=\(next)")
    }

    private static func keyCode(for name: String) -> CGKeyCode? {
        // Single char
        if name.count == 1, let ch = name.uppercased().unicodeScalars.first {
            let map: [UnicodeScalar: CGKeyCode] = [
                "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4,
                "I": 34, "J": 38, "K": 40, "L": 37, "M": 46, "N": 45, "O": 31, "P": 35,
                "Q": 12, "R": 15, "S": 1, "T": 17, "U": 32, "V": 9, "W": 13, "X": 7,
                "Y": 16, "Z": 6,
                "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
                "8": 28, "9": 25,
                "[": 33, "]": 30, "\\": 42, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44,
                "`": 50, "-": 27, "=": 24, " ": 49,
            ]
            if let c = map[ch] { return c }
        }
        switch name.lowercased() {
        case "space": return 49
        case "return", "enter": return 36
        case "tab": return 48
        case "escape", "esc": return 53
        case "delete", "backspace": return 51
        case "left": return 123
        case "right": return 124
        case "down": return 125
        case "up": return 126
        case "f1": return 122
        case "f2": return 120
        case "f3": return 99
        case "f4": return 118
        case "f5": return 96
        case "f6": return 97
        case "f7": return 98
        case "f8": return 100
        case "f9": return 101
        case "f10": return 109
        case "f11": return 103
        case "f12": return 111
        default: return nil
        }
    }

    // MARK: - System

    private func postSystem(_ id: String) {
        // Normalize so UI / config variants always match (underscores, hyphens, case).
        let key = id.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch key {
        case "mission_control", "missioncontrol":
            // Options+ opens Mission Control directly — more reliable than Ctrl+Up.
            openApp(name: "Mission Control", background: true) {
                self.systemEventsKey(code: 126, usingControl: true) // Ctrl+Up
            }
        case "app_expose", "appexpose", "application_windows", "app_windows":
            // App Exposé / App Windows — System Events so focused apps don't eat it.
            systemEventsKey(code: 125, usingControl: true) // Ctrl+Down
        case "previous_desktop", "desktop_left", "desktop_previous", "prev_desktop":
            switchDesktop(next: false)
        case "next_desktop", "desktop_right", "desktop_next":
            switchDesktop(next: true)
        case "launchpad":
            openApp(name: "Launchpad", background: false, fallback: nil)
        case "desktop", "show_desktop":
            systemEventsKey(code: 103, usingControl: false) // F11 often Show Desktop
            // Also try Mission Control desktop gesture fallback via keystroke.
        case "spotlight":
            postKeystroke(["cmd", "space"])
        default:
            DaemonLog.warn("Unknown system action \(id) (normalized=\(key))")
        }
    }

    private func openApp(name: String, background: Bool, fallback: (() -> Void)?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = background ? ["-g", "-a", name] : ["-a", name]
        do {
            try task.run()
            DaemonLog.info("open \(name)")
        } catch {
            DaemonLog.warn("open \(name) failed: \(error)")
            fallback?()
        }
    }

    /// Inject a key via System Events (session-level — same idea as Options+ agent).
    private func systemEventsKey(code: Int, usingControl: Bool) {
        let mods = usingControl ? " using control down" : ""
        let script = "tell application \"System Events\" to key code \(code)\(mods)"
        DispatchQueue.global(qos: .userInteractive).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    DaemonLog.info("System Events keyCode=\(code) ctrl=\(usingControl)")
                } else {
                    DaemonLog.warn("System Events keyCode=\(code) status=\(task.terminationStatus)")
                }
            } catch {
                DaemonLog.warn("System Events failed: \(error)")
            }
        }
    }

    // MARK: - Media

    private func postMedia(_ id: String) {
        // NX media keys via system-defined events
        let key: Int32?
        switch id {
        case "volume_up": key = NX_KEYTYPE_SOUND_UP
        case "volume_down": key = NX_KEYTYPE_SOUND_DOWN
        case "mute": key = NX_KEYTYPE_MUTE
        case "play_pause": key = NX_KEYTYPE_PLAY
        case "next": key = NX_KEYTYPE_NEXT
        case "previous": key = NX_KEYTYPE_PREVIOUS
        default:
            DaemonLog.warn("Unknown media \(id)")
            return
        }
        guard let key else { return }
        postSystemDefinedKey(key)
    }

    private func postSystemDefinedKey(_ key: Int32) {
        func post(_ down: Bool) {
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            if let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ), let cg = ev.cgEvent {
                cg.post(tap: .cghidEventTap)
            }
        }
        post(true)
        post(false)
    }
}

/// Weak box so ActionEngine can call features without ownership cycle.
final class MxFeaturesBox {
    var features: MxFeatures
    init(_ features: MxFeatures) { self.features = features }
}

// NX key type constants (from IOKit/hidsystem/ev_keymap.h)
private let NX_KEYTYPE_SOUND_UP: Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_MUTE: Int32 = 7
private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18
