import AppKit
import Foundation
import UserNotifications

/// Posts local notifications when mouse battery is low / critical.
/// Works with the UI closed (daemon-side).
enum BatteryNotifier {
    static let lowThreshold = 20
    static let criticalThreshold = 10

    /// Real device name from HID++ (e.g. "MX Master 3S"); never hardcode a model.
    static var deviceName: String = "Logitech mouse"

    private static var authorized = false
    /// 0 = none, 1 = low, 2 = critical — once per discharge cycle.
    private static var notifiedSeverity = 0

    /// `UNUserNotificationCenter` requires a real .app bundle; flat Helpers
    /// binaries crash with bundleProxyForCurrentProcess == nil.
    private static var isBundledApp: Bool {
        let path = Bundle.main.bundleURL.path
        if path.hasSuffix(".app") { return true }
        if Bundle.main.bundleURL.pathExtension == "app" { return true }
        if path.contains(".app/Contents/") { return true }
        return false
    }

    static func requestAuthorization() {
        guard isBundledApp else {
            DaemonLog.info("Battery notifications: osascript mode (not launched as .app)")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            authorized = granted
            if let error {
                DaemonLog.warn("notification auth error: \(error)")
            } else {
                DaemonLog.info("Battery notifications authorized=\(granted)")
            }
        }
    }

    static func evaluate(percent: Int, charging: Bool, deviceName name: String? = nil) {
        if let name, !name.isEmpty, name != "No device" {
            deviceName = name
        }

        if charging || percent > lowThreshold {
            notifiedSeverity = 0
            return
        }

        let severity: Int
        if percent <= criticalThreshold {
            severity = 2
        } else if percent <= lowThreshold {
            severity = 1
        } else {
            return
        }

        guard severity > notifiedSeverity else { return }
        notifiedSeverity = severity
        post(percent: percent, critical: severity >= 2)
    }

    private static func post(percent: Int, critical: Bool) {
        let name = deviceName.isEmpty ? "Logitech mouse" : deviceName
        let title = critical ? "\(name) — battery critical" : "\(name) — battery low"
        let body = critical
            ? "Battery at \(percent)%. Charge soon or the mouse may power off."
            : "Battery at \(percent)%. Consider charging your mouse."

        if isBundledApp {
            postUserNotification(title: title, body: body, critical: critical)
        } else {
            postOsascript(title: title, body: body)
        }
    }

    private static func postUserNotification(title: String, body: String, critical: Bool) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let ok = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            if !ok && !authorized {
                requestAuthorization()
                postOsascript(title: title, body: body)
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let id = critical ? "logioptions.battery.critical" : "logioptions.battery.low"
            let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            center.add(req) { error in
                if let error {
                    DaemonLog.warn("battery notification failed: \(error)")
                    postOsascript(title: title, body: body)
                } else {
                    DaemonLog.info("battery notification posted critical=\(critical) name=\(deviceName)")
                }
            }
        }
    }

    private static func postOsascript(title: String, body: String) {
        let t = title.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let b = body.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(b)\" with title \"\(t)\" sound name \"default\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            DaemonLog.info("battery notification via osascript title=\(title)")
        } catch {
            DaemonLog.warn("osascript notification failed: \(error)")
        }
    }
}
