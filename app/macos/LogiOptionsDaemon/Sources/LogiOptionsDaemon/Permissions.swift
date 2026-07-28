import ApplicationServices
import IOKit.hid

/// Daemon-side permission checks.
///
/// **Accessibility** is required for CGEvent injection and System Events.
/// **Input Monitoring is not required** — we talk to our own MX Master via
/// IOHID HID++, we do not install global listen-only event taps.
enum Permissions {
  static func accessibilityTrusted() -> Bool {
    if AXIsProcessTrusted() { return true }
    return IOHIDCheckAccess(kIOHIDRequestTypePostEvent) == kIOHIDAccessTypeGranted
  }

  /// Reported for UI only; not a hard requirement.
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
    let message = accessibilityTrusted()
      ? "Accessibility already granted"
      : "Accessibility missing — waiting for explicit Grant action"
    DaemonLog.info(message)
  }

  static func shouldRequestFromUser(arguments: [String]) -> Bool {
    arguments.contains("--request-accessibility")
  }

  /// Called only after an explicit Grant or Start-daemon action.
  static func requestForDaemonFromUser() {
    if accessibilityTrusted() {
      DaemonLog.info("Accessibility already granted")
      return
    }
    _ = IOHIDRequestAccess(kIOHIDRequestTypePostEvent)
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
    ] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(options)
    DaemonLog.info("User-requested Accessibility registration → trusted=\(trusted)")
  }
}
