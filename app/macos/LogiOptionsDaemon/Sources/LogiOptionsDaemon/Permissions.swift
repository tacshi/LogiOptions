import ApplicationServices
import IOKit.hid

/// Daemon-side permission checks.
///
/// **Accessibility** is required for CGEvent injection and System Events.
/// **Input Monitoring** is required by macOS to open direct Bluetooth HID
/// interfaces, even though the daemon does not install a global event tap.
enum Permissions {
  static func accessibilityTrusted() -> Bool {
    if AXIsProcessTrusted() { return true }
    return IOHIDCheckAccess(kIOHIDRequestTypePostEvent) == kIOHIDAccessTypeGranted
  }

  static func inputMonitoringTrusted() -> Bool {
    let hid = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    if hid == kIOHIDAccessTypeGranted { return true }
    if hid == kIOHIDAccessTypeDenied { return false }
    if #available(macOS 10.15, *) {
      return CGPreflightListenEventAccess()
    }
    return true
  }

  /// Startup checks are deliberately read-only. System Settings is opened only
  /// by the user's explicit Grant action in the Flutter app.
  static func checkForDaemon() {
    DaemonLog.info(
      "Permissions accessibility=\(accessibilityTrusted()) "
        + "inputMonitoring=\(inputMonitoringTrusted())"
    )
  }

  static func shouldRequestFromUser(arguments: [String]) -> Bool {
    arguments.contains("--request-accessibility")
  }

  /// Called once for every installed app version and after an explicit Grant
  /// or Start-daemon action.
  static func requestForDaemonFromUser() {
    _ = IOHIDRequestAccess(kIOHIDRequestTypePostEvent)
    _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
    ] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(options)
    DaemonLog.info(
      "User-requested permission registration "
        + "accessibility=\(trusted) "
        + "inputMonitoring=\(inputMonitoringTrusted())"
    )
  }
}
