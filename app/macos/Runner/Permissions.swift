import ApplicationServices
import AppKit
import Foundation
import IOKit.hid

/// Privacy permissions for remaps / scroll injection.
///
/// **Accessibility** is required (CGEvent post, System Events for Spaces).
/// **Input Monitoring** is required by macOS for the daemon to open direct
/// Bluetooth HID interfaces.
///
/// Startup only reads trust. The explicit in-app Grant action opens System
/// Settings, then polling clears the banner after the user grants access.
enum Permissions {
  struct Status {
    var accessibility: Bool
    var inputMonitoring: Bool

    var allGranted: Bool { accessibility && inputMonitoring }
  }

  enum Pane {
    case accessibility
    case inputMonitoring
  }

  private static var trustPollTimer: Timer?

  static func current() -> Status {
    Status(
      accessibility: accessibilityGranted(),
      inputMonitoring: inputMonitoringGranted()
    )
  }

  /// Registers the UI process for Accessibility. The daemon registers itself
  /// for both required permissions through its own RPC/startup flow.
  static func requestAccessibilityFromUI() {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
    _ = IOHIDRequestAccess(kIOHIDRequestTypePostEvent)
    openSystemSettings(pane: .accessibility)
    startTrustPolling()
  }

  static func openSystemSettings(pane: Pane) {
    let anchors: [String]
    switch pane {
    case .accessibility:
      anchors = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
      ]
    case .inputMonitoring:
      anchors = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
      ]
    }
    for a in anchors {
      if let url = URL(string: a), NSWorkspace.shared.open(url) {
        NSLog("[LogiOptions] opened Settings: \(a)")
        return
      }
    }
  }

  /// Poll until Accessibility is granted, then notify UI.
  private static func startTrustPolling() {
    stopTrustPolling()
    guard !accessibilityGranted() else { return }
    let timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { t in
      if accessibilityGranted() {
        NSLog("[LogiOptions] Accessibility granted — stopping poll")
        t.invalidate()
        trustPollTimer = nil
        // Bring app forward so user leaves Settings; system sheet may still
        // need one click if it was already showing from an older build.
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .logiPermissionsChanged, object: nil)
      }
    }
    // Timer needs a run-loop mode that fires while Settings is frontmost.
    RunLoop.main.add(timer, forMode: .common)
    trustPollTimer = timer
  }

  private static func stopTrustPolling() {
    trustPollTimer?.invalidate()
    trustPollTimer = nil
  }

  // MARK: - Checks

  private static func accessibilityGranted() -> Bool {
    if AXIsProcessTrusted() { return true }
    return IOHIDCheckAccess(kIOHIDRequestTypePostEvent) == kIOHIDAccessTypeGranted
  }

  private static func inputMonitoringGranted() -> Bool {
    let hid = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    if hid == kIOHIDAccessTypeGranted { return true }
    if hid == kIOHIDAccessTypeDenied { return false }
    if #available(macOS 10.15, *) {
      return CGPreflightListenEventAccess()
    }
    return true
  }
}

extension Notification.Name {
  static let logiPermissionsChanged = Notification.Name("com.logioptions.permissionsChanged")
}
