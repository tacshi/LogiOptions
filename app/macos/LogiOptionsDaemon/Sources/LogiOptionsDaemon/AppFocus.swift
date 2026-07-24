import AppKit
import Foundation

final class AppFocusMonitor {
    private(set) var frontBundleId: String?
    var onChange: ((String?) -> Void)?

    func start() {
        frontBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func activated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let bid = app?.bundleIdentifier
        if bid != frontBundleId {
            frontBundleId = bid
            onChange?(bid)
        }
    }
}
