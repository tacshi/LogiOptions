import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var permissionsObserver: NSObjectProtocol?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Default size large enough for device art + side panel + gesture editors.
    let size = NSSize(width: 1280, height: 860)
    self.setContentSize(size)
    self.minSize = NSSize(width: 960, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerPermissionsChannel(flutterViewController)
    registerDaemonChannel(flutterViewController)

    super.awakeFromNib()

    // Ensure HID++ helper is up once the UI window is live.
    if let app = NSApp.delegate as? AppDelegate {
      app.startDaemonIfNeeded()
    }

    // Accessibility only — open Settings once if missing (no sticky dual prompts).
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      _ = Permissions.requestMissing(openSettingsIfNeeded: true)
    }
  }

  deinit {
    if let permissionsObserver {
      NotificationCenter.default.removeObserver(permissionsObserver)
    }
  }

  private func registerPermissionsChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.logioptions/permissions",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getStatus":
        let s = Permissions.current()
        result([
          "accessibility": s.accessibility,
          "inputMonitoring": s.inputMonitoring,
        ])
      case "request":
        Permissions.requestAccessibilityFromUI()
        let s = Permissions.current()
        result([
          "accessibility": s.accessibility,
          "inputMonitoring": s.inputMonitoring,
        ])
      case "openAccessibility":
        Permissions.requestAccessibilityFromUI()
        result(true)
      case "openInputMonitoring":
        // Not required; keep method for older UI builds.
        Permissions.openSystemSettings(pane: .inputMonitoring)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Push status to Flutter when poll detects Accessibility grant.
    permissionsObserver = NotificationCenter.default.addObserver(
      forName: .logiPermissionsChanged,
      object: nil,
      queue: .main
    ) { _ in
      let s = Permissions.current()
      channel.invokeMethod("onPermissionsChanged", arguments: [
        "accessibility": s.accessibility,
        "inputMonitoring": s.inputMonitoring,
      ])
    }
  }

  /// Start daemon from Settings when RPC is offline (after Stop).
  private func registerDaemonChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.logioptions/daemon",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        guard let app = NSApp.delegate as? AppDelegate else {
          result(FlutterError(code: "no_delegate", message: "AppDelegate missing", details: nil))
          return
        }
        let ok = app.startDaemon(force: true)
        result(["ok": ok])
      case "isRunning":
        // Best-effort: socket probe is owned by AppDelegate; reuse start path checks via pgrep.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "LogiOptionsDaemon"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        result(["running": task.terminationStatus == 0])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
