import Cocoa
import FlutterMacOS
import Darwin

@main
class AppDelegate: FlutterAppDelegate {
  private static var didAttemptDaemonStart = false
  private var applicationsChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    registerApplicationsChannel()
    _ = Permissions.current()
    startDaemonIfNeeded()
  }

  private func registerApplicationsChannel() {
    guard
      let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      NSLog("[LogiOptions] Flutter view unavailable for applications channel")
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.logioptions/applications",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "listInstalled":
        DispatchQueue.global(qos: .userInitiated).async {
          let applications = InstalledApplications.scan()
          DispatchQueue.main.async { result(applications) }
        }
      case "browse":
        InstalledApplications.browse(result: result)
      case "browseFile":
        InstalledApplications.browseFile(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    applicationsChannel = channel
  }

  func startDaemonIfNeeded() {
    let currentVersion = DaemonInstallPolicy.versionIdentifier()
    let defaults = UserDefaults.standard
    let lastHandledVersion = defaults.string(
      forKey: DaemonInstallPolicy.handledVersionKey
    )
    let isNewVersion = DaemonInstallPolicy.shouldTransition(
      currentVersion: currentVersion,
      lastHandledVersion: lastHandledVersion
    )
    if isNewVersion {
      NSLog(
        "[LogiOptions] installed version changed "
          + "\(lastHandledVersion ?? "none") → \(currentVersion)"
      )
    }
    let started = ensureDaemonRunning(
      force: isNewVersion,
      requestAccessibility: isNewVersion
    )
    if isNewVersion && started {
      defaults.set(
        currentVersion,
        forKey: DaemonInstallPolicy.handledVersionKey
      )
    }
  }

  /// Start (or restart) the daemon — used after Settings → Stop.
  @discardableResult
  func startDaemon(
    force: Bool = true,
    requestAccessibility: Bool = false
  ) -> Bool {
    let started = ensureDaemonRunning(
      force: force,
      requestAccessibility: requestAccessibility
    )
    if !started {
      NSLog("[LogiOptions] startDaemon failed readiness check")
    }
    return started
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    NSLog("[LogiOptions] UI quitting — LogiOptionsDaemon keeps running")
  }

  // MARK: - Embedded daemon

  private func ensureDaemonRunning(
    force: Bool,
    requestAccessibility: Bool
  ) -> Bool {
    if !force && Self.didAttemptDaemonStart { return true }
    Self.didAttemptDaemonStart = true

    guard let daemonURL = locateDaemonBinary() else {
      NSLog("[LogiOptions] LogiOptionsDaemon not found in app bundle")
      return false
    }

    if !force && isSocketLive() && !daemonPIDs().isEmpty {
      NSLog("[LogiOptions] daemon already running — keep it")
      return true
    }

    // Kill orphans / stale locks so a clean bind succeeds.
    if !daemonPIDs().isEmpty {
      stopExistingDaemons()
      Thread.sleep(forTimeInterval: 0.15)
    }
    try? FileManager.default.removeItem(atPath: "/tmp/logioptions.sock")
    try? FileManager.default.removeItem(atPath: "/tmp/logioptions.daemon.lock")
    guard launchDetached(
      daemonURL,
      requestAccessibility: requestAccessibility
    ) else {
      return false
    }
    return waitForDaemonReady()
  }

  /// Require a stable RPC process before recording an installed version as
  /// handled. A helper that binds and immediately crashes must be retried.
  private func waitForDaemonReady() -> Bool {
    let deadline = Date().addingTimeInterval(3)
    var liveSince: Date?
    while Date() < deadline {
      let live = isSocketLive() && !daemonPIDs().isEmpty
      if live {
        let firstLive = liveSince ?? Date()
        liveSince = firstLive
        if Date().timeIntervalSince(firstLive) >= 0.6 {
          return true
        }
      } else {
        liveSince = nil
      }
      Thread.sleep(forTimeInterval: 0.06)
    }
    let pids = daemonPIDs()
    NSLog(
      "[LogiOptions] daemon readiness failed "
        + "socket=\(isSocketLive()) pids=\(pids)"
    )
    return false
  }

  private func stopExistingDaemons() {
    for pid in daemonPIDs() {
      NSLog("[LogiOptions] stopping daemon pid=\(pid)")
      kill(pid, SIGTERM)
    }
    for _ in 0..<30 {
      if daemonPIDs().isEmpty { break }
      Thread.sleep(forTimeInterval: 0.05)
    }
    for pid in daemonPIDs() {
      kill(pid, SIGKILL)
    }
    try? FileManager.default.removeItem(atPath: "/tmp/logioptions.sock")
    try? FileManager.default.removeItem(atPath: "/tmp/logioptions.daemon.lock")
  }

  private func daemonPIDs() -> [pid_t] {
    // Match both flat binary and …/LogiOptionsDaemon.app/…/LogiOptionsDaemon
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", "LogiOptionsDaemon"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do {
      try task.run()
      task.waitUntilExit()
    } catch {
      return []
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    // Filter out this process's shell / pgrep noise: only numeric pids.
    return text.split(whereSeparator: \.isNewline).compactMap { line -> pid_t? in
      let s = line.trimmingCharacters(in: .whitespaces)
      // pgrep -f prints "pid" only with default; with -f default is still pid only
      return pid_t(s)
    }
  }

  private func isSocketLive() -> Bool {
    let path = "/tmp/logioptions.sock"
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
      pathBytes.withUnsafeBufferPointer { buf in
        memcpy(ptr, buf.baseAddress!, min(buf.count, 104))
      }
    }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    return withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
      }
    }
  }

  /// Always launch via nohup on the in-app binary (reliable + logged).
  /// Prefer the binary inside LogiOptionsDaemon.app for UserNotifications.
  private func launchDetached(
    _ daemonURL: URL,
    requestAccessibility: Bool
  ) -> Bool {
    let outPath = "/tmp/logioptions.daemon.out.log"
    let errPath = "/tmp/logioptions.daemon.err.log"
    if !FileManager.default.fileExists(atPath: outPath) {
      FileManager.default.createFile(atPath: outPath, contents: nil)
    }
    if !FileManager.default.fileExists(atPath: errPath) {
      FileManager.default.createFile(atPath: errPath, contents: nil)
    }

    let appBinary = daemonURL
      .deletingLastPathComponent()
      .appendingPathComponent("LogiOptionsDaemon.app/Contents/MacOS/LogiOptionsDaemon")
    let exec: URL
    if FileManager.default.isExecutableFile(atPath: appBinary.path) {
      exec = appBinary
    } else {
      exec = daemonURL
    }

    NSLog("[LogiOptions] launching daemon: \(exec.path)")
    return launchNohup(
      exec,
      outPath: outPath,
      errPath: errPath,
      requestAccessibility: requestAccessibility
    )
  }

  private func launchNohup(
    _ daemonURL: URL,
    outPath: String,
    errPath: String,
    requestAccessibility: Bool
  ) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    let permissionArgument = requestAccessibility
      ? " --request-accessibility"
      : ""
    process.arguments = [
      "-c",
      "nohup \"\(daemonURL.path)\"\(permissionArgument) >>\"\(outPath)\" 2>>\"\(errPath)\" </dev/null & disown || true",
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus == 0
    } catch {
      NSLog("[LogiOptions] failed to start daemon: \(error)")
      return false
    }
  }

  private func locateDaemonBinary() -> URL? {
    let bundle = Bundle.main
    let candidates: [URL] = [
      bundle.bundleURL.appendingPathComponent("Contents/Helpers/LogiOptionsDaemon"),
      bundle.bundleURL.appendingPathComponent("Contents/MacOS/LogiOptionsDaemon"),
    ]
    for url in candidates {
      if FileManager.default.isExecutableFile(atPath: url.path) {
        return url
      }
    }
    if let aux = bundle.url(forAuxiliaryExecutable: "LogiOptionsDaemon"),
       FileManager.default.isExecutableFile(atPath: aux.path) {
      return aux
    }
    return nil
  }
}

private enum InstalledApplications {
  static func scan() -> [[String: Any]] {
    let manager = FileManager.default
    let roots = [
      URL(fileURLWithPath: "/Applications", isDirectory: true),
      URL(fileURLWithPath: "/System/Applications", isDirectory: true),
      manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
    ]
    var seen = Set<String>()
    var results: [[String: Any]] = []
    for root in roots where manager.fileExists(atPath: root.path) {
      guard let enumerator = manager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) else { continue }
      for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
        guard let application = record(for: url),
              let bundleId = application["bundleId"] as? String,
              seen.insert(bundleId).inserted else { continue }
        results.append(application)
      }
    }
    return results.sorted {
      ($0["name"] as? String ?? "").localizedCaseInsensitiveCompare(
        $1["name"] as? String ?? ""
      ) == .orderedAscending
    }
  }

  static func browse(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.title = "Choose an application"
    panel.prompt = "Add Application"
    panel.allowedFileTypes = ["app"]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.begin { response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      result(record(for: url))
    }
  }

  static func browseFile(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.title = "Choose a file"
    panel.prompt = "Choose"
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.begin { response in
      result(response == .OK ? panel.url?.path : nil)
    }
  }

  private static func record(for url: URL) -> [String: Any]? {
    guard let bundle = Bundle(url: url),
          let bundleId = bundle.bundleIdentifier else { return nil }
    let name = (
      bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? url.deletingPathExtension().lastPathComponent
    )
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    icon.size = NSSize(width: 64, height: 64)
    var iconData: Data?
    if let tiff = icon.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff) {
      iconData = bitmap.representation(using: .png, properties: [:])
    }
    var record: [String: Any] = [
      "bundleId": bundleId,
      "name": name,
      "path": url.path,
    ]
    if let iconData {
      record["icon"] = FlutterStandardTypedData(bytes: iconData)
    }
    return record
  }
}
