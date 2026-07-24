import ApplicationServices
import AppKit
import Foundation
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

  /// Prompt Accessibility at most once; open Settings without sticky re-prompts.
  static func requestForDaemon() {
    if accessibilityTrusted() {
      DaemonLog.info("Accessibility already granted")
      return
    }
    // Register for PostEvent (same TCC family as Accessibility on some builds).
    _ = IOHIDRequestAccess(kIOHIDRequestTypePostEvent)
    // Do not pass prompt:true every launch — that re-shows the lock sheet.
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    let ax = AXIsProcessTrustedWithOptions(opts)
    DaemonLog.info("Accessibility check → trusted=\(ax) (Settings only if still missing)")
    if !accessibilityTrusted() {
      openPrivacyPane(anchor: "Privacy_Accessibility")
      startTrustPolling()
    }
  }

  private static var pollTimer: Timer?

  private static func startTrustPolling() {
    pollTimer?.invalidate()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
      if accessibilityTrusted() {
        DaemonLog.info("Accessibility granted (daemon poll)")
        t.invalidate()
        pollTimer = nil
      }
    }
    if let pollTimer {
      RunLoop.main.add(pollTimer, forMode: .common)
    }
  }

  private static func openPrivacyPane(anchor: String) {
    let candidates = [
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
      "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
    ]
    for c in candidates {
      if let url = URL(string: c), NSWorkspace.shared.open(url) {
        DaemonLog.info("opened Settings \(anchor)")
        return
      }
    }
  }
}
