import Cocoa
import FlutterMacOS
import Darwin

@main
class AppDelegate: FlutterAppDelegate {
  private static var didAttemptDaemonStart = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    _ = Permissions.requestMissing(openSettingsIfNeeded: false)
    startDaemonIfNeeded()
  }

  func startDaemonIfNeeded() {
    ensureDaemonRunning(force: false)
  }

  /// Start (or restart) the daemon — used after Settings → Stop.
  @discardableResult
  func startDaemon(force: Bool = true) -> Bool {
    ensureDaemonRunning(force: force)
    // Poll until RPC socket is up (openApplication / nohup are async).
    for _ in 0..<25 {
      if isSocketLive() { return true }
      Thread.sleep(forTimeInterval: 0.12)
    }
    let pids = daemonPIDs()
    let live = isSocketLive()
    NSLog("[LogiOptions] startDaemon done socket=\(live) pids=\(pids)")
    return live || !pids.isEmpty
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

  private func ensureDaemonRunning(force: Bool) {
    if !force && Self.didAttemptDaemonStart { return }
    Self.didAttemptDaemonStart = true

    guard let daemonURL = locateDaemonBinary() else {
      NSLog("[LogiOptions] LogiOptionsDaemon not found in app bundle")
      return
    }

    if isSocketLive() && !daemonPIDs().isEmpty {
      NSLog("[LogiOptions] daemon already running — keep it")
      return
    }

    // Kill orphans / stale locks so a clean bind succeeds.
    if !daemonPIDs().isEmpty {
      stopExistingDaemons()
      Thread.sleep(forTimeInterval: 0.15)
    }
    try? FileManager.default.removeItem(atPath: "/tmp/logioptions.sock")
    try? FileManager.default.removeItem(atPath: "/tmp/logioptions.daemon.lock")
    launchDetached(daemonURL)
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
    withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
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
  private func launchDetached(_ daemonURL: URL) {
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
    launchNohup(exec, outPath: outPath, errPath: errPath)
  }

  private func launchNohup(_ daemonURL: URL, outPath: String, errPath: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [
      "-c",
      "nohup \"\(daemonURL.path)\" >>\"\(outPath)\" 2>>\"\(errPath)\" </dev/null & disown || true",
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      NSLog("[LogiOptions] failed to start daemon: \(error)")
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
