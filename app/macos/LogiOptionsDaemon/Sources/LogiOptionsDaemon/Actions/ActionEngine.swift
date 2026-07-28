import AppKit
import CoreGraphics
import Foundation

enum NavigationAction: Equatable {
    case auxiliaryMouseButton(Int64)
    case keystroke([String])
}

enum MousePress: Equatable {
    case standard(String)
    case auxiliary(Int64)
    case momentaryKeystroke([String])
}

/// Executes host-side actions (requires Accessibility for some paths).
final class ActionEngine {
    weak var features: DeviceFeaturesBox?

    /// Serial queue for System Events injects. NSAppleScript is not thread-safe;
    /// work stays off the HID/main path so gesture tracking is never blocked.
    private let systemEventsQueue = DispatchQueue(
        label: "logioptions.systemevents",
        qos: .userInteractive
    )
    /// Compiled scripts — avoids forking `/usr/bin/osascript` (~150 ms) per gesture.
    private var systemEventsScripts: [String: NSAppleScript] = [:]
    private var systemEventsWarmed = false

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
        case .open(let kind, let value):
            openTarget(kind: kind, value: value)
        case .smartShiftToggle:
            _ = features?.features.toggleSmartShift()
        case .gesture:
            // Nested gesture specs are handled by GestureTracker
            break
        }
    }

    private func openTarget(kind: String, value: String) {
        let workspace = NSWorkspace.shared
        switch kind.lowercased() {
        case "url":
            if let url = URL(string: value) { workspace.open(url) }
        case "app", "file":
            workspace.open(URL(fileURLWithPath: value))
        default:
            DaemonLog.warn("Unknown open target kind \(kind)")
        }
    }

    // MARK: - Mouse

    private func postMouseButton(_ name: String) {
        guard let press = beginMouseButton(name) else { return }
        endMouseButton(press)
    }

    /// Preserve physical down/up timing for remapped mouse buttons so dragging
    /// and press-and-hold work. Momentary keyboard navigation fires on down.
    func beginMouseButton(_ name: String) -> MousePress? {
        guard let press = Self.mousePress(
            for: name,
            frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        ) else {
            DaemonLog.warn("Unknown mouse button \(name)")
            return nil
        }
        let loc = CGEvent(source: nil)?.location ?? .zero
        switch press {
        case .standard(let button):
            postStandardMouseButton(button, down: true, at: loc)
        case .auxiliary(let buttonNumber):
            postAuxiliaryMouseButton(buttonNumber, down: true, at: loc)
        case .momentaryKeystroke(let keys):
            postKeystroke(keys)
        }
        return press
    }

    func endMouseButton(_ press: MousePress) {
        let loc = CGEvent(source: nil)?.location ?? .zero
        switch press {
        case .standard(let button):
            postStandardMouseButton(button, down: false, at: loc)
        case .auxiliary(let buttonNumber):
            postAuxiliaryMouseButton(buttonNumber, down: false, at: loc)
        case .momentaryKeystroke:
            break
        }
    }

    static func mousePress(
        for name: String,
        frontmostBundleIdentifier: String?
    ) -> MousePress? {
        let normalized = name.lowercased()
        if ["left", "right", "middle"].contains(normalized) {
            return .standard(normalized)
        }
        guard let navigation = navigationAction(
            for: normalized,
            frontmostBundleIdentifier: frontmostBundleIdentifier
        ) else { return nil }
        switch navigation {
        case .auxiliaryMouseButton(let number):
            return .auxiliary(number)
        case .keystroke(let keys):
            return .momentaryKeystroke(keys)
        }
    }

    static func navigationAction(
        for name: String,
        frontmostBundleIdentifier: String?
    ) -> NavigationAction? {
        let normalizedName = name.lowercased()
        if frontmostBundleIdentifier?.lowercased() == "com.apple.finder" {
            switch normalizedName {
            case "back":
                return .keystroke(["cmd", "["])
            case "forward":
                return .keystroke(["cmd", "]"])
            default:
                return nil
            }
        }

        switch normalizedName {
        case "back":
            // macOS auxiliary button 3 is commonly treated as Back.
            return .auxiliaryMouseButton(3)
        case "forward":
            return .auxiliaryMouseButton(4)
        default:
            return nil
        }
    }

    private func postStandardMouseButton(
        _ name: String,
        down: Bool,
        at location: CGPoint
    ) {
        let type: CGEventType
        let button: CGMouseButton
        switch name {
        case "left":
            type = down ? .leftMouseDown : .leftMouseUp
            button = .left
        case "right":
            type = down ? .rightMouseDown : .rightMouseUp
            button = .right
        case "middle":
            type = down ? .otherMouseDown : .otherMouseUp
            button = .center
        default:
            return
        }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) else { return }
        if button == .center {
            event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        }
        event.post(tap: .cghidEventTap)
    }

    private func postAuxiliaryMouseButton(
        _ buttonNumber: Int64,
        down: Bool,
        at location: CGPoint
    ) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: down ? .otherMouseDown : .otherMouseUp,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        event.post(tap: .cghidEventTap)
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
    /// System Events at session level keeps the system slide animation. Same
    /// semantics as before — only the transport is faster: cached in-process
    /// `NSAppleScript` on a background queue instead of spawning `osascript`
    /// (~150 ms) every time. Gesture thresholds are unchanged.
    private func switchDesktop(next: Bool) {
        let keyCode = next ? 124 : 123
        DaemonLog.info("switchDesktop next=\(next) scheduled")
        systemEventsKey(code: keyCode, usingControl: true) { [weak self] ok, ms in
            if ok {
                DaemonLog.info(String(
                    format: "switchDesktop next=%@ via System Events %.1fms",
                    next ? "true" : "false",
                    ms
                ))
            } else {
                DaemonLog.warn("switchDesktop SE failed — CGEvent fallback")
                DispatchQueue.main.async {
                    self?.forceControlArrow(next: next)
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
    ///
    /// Always async on `systemEventsQueue`. Returns immediately to the caller so
    /// gesture `fired` can be set without re-entrancy. Prefer cached NSAppleScript;
    /// fall back to `osascript` Process only if AppleScript fails.
    private func systemEventsKey(
        code: Int,
        usingControl: Bool,
        completion: ((Bool, Double) -> Void)? = nil
    ) {
        systemEventsQueue.async { [weak self] in
            guard let self else { return }
            let t0 = CACurrentMediaTime()
            let ok = self.runSystemEventsNow(code: code, usingControl: usingControl)
            let ms = (CACurrentMediaTime() - t0) * 1000
            if let completion {
                completion(ok, ms)
            } else if ok {
                DaemonLog.info(String(
                    format: "System Events keyCode=%d ctrl=%@ %.1fms",
                    code,
                    usingControl ? "true" : "false",
                    ms
                ))
            } else {
                DaemonLog.warn("System Events keyCode=\(code) failed")
            }
        }
    }

    /// Must run only on `systemEventsQueue`.
    private func runSystemEventsNow(code: Int, usingControl: Bool) -> Bool {
        warmSystemEvents()
        let mods = usingControl ? " using control down" : ""
        let source = "tell application \"System Events\" to key code \(code)\(mods)"

        let script: NSAppleScript
        if let cached = systemEventsScripts[source] {
            script = cached
        } else if let created = NSAppleScript(source: source) {
            systemEventsScripts[source] = created
            script = created
        } else {
            return runSystemEventsViaProcess(code: code, usingControl: usingControl)
        }

        var err: NSDictionary?
        script.executeAndReturnError(&err)
        if err == nil { return true }

        DaemonLog.warn("NSAppleScript keyCode=\(code) err=\(err!) — osascript fallback")
        return runSystemEventsViaProcess(code: code, usingControl: usingControl)
    }

    private func warmSystemEvents() {
        guard !systemEventsWarmed else { return }
        systemEventsWarmed = true
        // Touch System Events once (Automation TCC) without injecting a key.
        if let probe = NSAppleScript(source: "tell application \"System Events\" to get name") {
            var err: NSDictionary?
            probe.executeAndReturnError(&err)
            if let err {
                DaemonLog.warn("System Events warm probe: \(err)")
            } else {
                DaemonLog.info("System Events warm OK")
            }
        }
        // Pre-compile the keys we use for Spaces / Mission Control / App Exposé.
        for (code, ctrl) in [(123, true), (124, true), (125, true), (126, true), (103, false)] {
            let mods = ctrl ? " using control down" : ""
            let source = "tell application \"System Events\" to key code \(code)\(mods)"
            if systemEventsScripts[source] == nil, let s = NSAppleScript(source: source) {
                systemEventsScripts[source] = s
            }
        }
    }

    private func runSystemEventsViaProcess(code: Int, usingControl: Bool) -> Bool {
        let mods = usingControl ? " using control down" : ""
        let script = "tell application \"System Events\" to key code \(code)\(mods)"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            DaemonLog.warn("System Events Process failed: \(error)")
            return false
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
final class DeviceFeaturesBox {
    var features: DeviceFeatures
    init(_ features: DeviceFeatures) { self.features = features }
}

// NX key type constants (from IOKit/hidsystem/ev_keymap.h)
private let NX_KEYTYPE_SOUND_UP: Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_MUTE: Int32 = 7
private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18
