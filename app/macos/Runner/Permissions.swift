import ApplicationServices
import AppKit
import Foundation
import IOKit.hid

/// Privacy permissions for remaps / scroll injection.
///
/// **Accessibility** is required (CGEvent post, System Events for Spaces).
/// **Input Monitoring is not required** for our architecture: we open our own
/// Logitech HID++ device via IOHID and inject events — we do not listen to
/// global key/mouse taps from other apps.
///
/// The system “would like to control this computer” sheet cannot be closed by
/// third-party code. We avoid re-showing it: open System Settings once, then
/// poll until granted so the in-app banner clears automatically.
enum Permissions {
  struct Status {
    var accessibility: Bool
    /// Kept for API compatibility; always reported, never required.
    var inputMonitoring: Bool

    /// Only Accessibility gates remaps.
    var allGranted: Bool { accessibility }
  }

  enum Pane {
    case accessibility
    case inputMonitoring
  }

  private static var didOfferAccessibilityThisSession = false
  private static var trustPollTimer: Timer?

  static func current() -> Status {
    Status(
      accessibility: accessibilityGranted(),
      inputMonitoring: inputMonitoringGranted()
    )
  }

  /// Offer Accessibility at most once per process; open Settings (no repeated modal).
  @discardableResult
  static func requestMissing(openSettingsIfNeeded: Bool = true) -> Status {
    if accessibilityGranted() {
      stopTrustPolling()
      return current()
    }

    // Prefer Settings deep-link over AX prompt sheet — the sheet sticks around
    // after the user toggles access on and cannot be dismissed by us.
    if openSettingsIfNeeded && !didOfferAccessibilityThisSession {
      didOfferAccessibilityThisSession = true
      // One quiet AX registration (no prompt sheet if already listed).
      let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(opts)
      _ = IOHIDRequestAccess(kIOHIDRequestTypePostEvent)
      openSystemSettings(pane: .accessibility)
      startTrustPolling()
      NSLog("[LogiOptions] Accessibility: opened Settings (no sticky prompt sheet)")
    } else if !didOfferAccessibilityThisSession {
      // Explicit request without Settings (e.g. early launch).
      didOfferAccessibilityThisSession = true
      let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(opts)
      _ = IOHIDRequestAccess(kIOHIDRequestTypePostEvent)
      startTrustPolling()
    }

    return current()
  }

  /// User tapped Grant — open Accessibility only (never Input Monitoring).
  static func requestAccessibilityFromUI() {
    didOfferAccessibilityThisSession = true
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
      // Optional; not required for LogiOptions.
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

  /// Poll until Accessibility is granted, then notify UI (banner can hide).
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
