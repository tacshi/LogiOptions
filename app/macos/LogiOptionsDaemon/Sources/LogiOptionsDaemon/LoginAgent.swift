import Foundation

/// User LaunchAgent so LogiOptionsDaemon survives UI quit and starts at login.
enum LoginAgent {
    static let label = "com.logioptions.daemon"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// Prefer the binary inside `LogiOptionsDaemon.app` for notifications/TCC.
    static var executablePath: String {
        let argv0 = CommandLine.arguments[0]
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let resolved: String
        if realpath(argv0, &buf) != nil {
            resolved = String(cString: buf)
        } else {
            resolved = URL(fileURLWithPath: argv0).standardizedFileURL.path
        }
        let appBin = resolved + ".app/Contents/MacOS/LogiOptionsDaemon"
        if FileManager.default.isExecutableFile(atPath: appBin) {
            return appBin
        }
        if resolved.contains(".app/Contents/MacOS/") {
            return resolved
        }
        return resolved
    }

    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func isLoaded() -> Bool {
        let uid = getuid()
        return runLaunchctl(["print", "gui/\(uid)/\(label)"]).status == 0
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            return installAndLoad(replaceRunning: false)
        }
        return unloadAndRemove()
    }

    /// After a manual Start: refresh the plist path only. Do **not** bootout —
    /// that races the process that just launched and causes lock thrash.
    static func ensureLoadedWithCurrentBinary() {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        guard writePlist(executable: executablePath) else { return }
        if !isLoaded() {
            let uid = getuid()
            let domain = "gui/\(uid)"
            var r = runLaunchctl(["bootstrap", domain, plistURL.path])
            if r.status != 0 {
                r = runLaunchctl(["load", "-w", plistURL.path])
            }
            _ = runLaunchctl(["enable", "\(domain)/\(label)"])
            DaemonLog.info("LoginAgent soft-load status=\(r.status)")
        } else {
            DaemonLog.info("LoginAgent already loaded — plist path refreshed only")
        }
    }

    /// Stop for this session without deleting the login preference.
    static func stopSession() {
        let uid = getuid()
        let domain = "gui/\(uid)"
        _ = runLaunchctl(["bootout", "\(domain)/\(label)"])
        _ = runLaunchctl(["unload", plistURL.path])
        DaemonLog.info("LoginAgent session stopped")
    }

    private static func installAndLoad(replaceRunning: Bool) -> Bool {
        let exe = executablePath
        guard FileManager.default.isExecutableFile(atPath: exe) else {
            DaemonLog.warn("LoginAgent: binary not executable at \(exe)")
            return false
        }
        guard writePlist(executable: exe) else { return false }

        let uid = getuid()
        let domain = "gui/\(uid)"
        if replaceRunning {
            _ = runLaunchctl(["bootout", "\(domain)/\(label)"])
            _ = runLaunchctl(["unload", plistURL.path])
        }
        if !isLoaded() {
            var r = runLaunchctl(["bootstrap", domain, plistURL.path])
            if r.status != 0 {
                r = runLaunchctl(["load", "-w", plistURL.path])
            }
            _ = runLaunchctl(["enable", "\(domain)/\(label)"])
            DaemonLog.info("LoginAgent enabled path=\(exe) bootstrap=\(r.status)")
        }
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    private static func writePlist(executable exe: String) -> Bool {
        let agents = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        	<key>Label</key>
        	<string>\(label)</string>
        	<key>ProgramArguments</key>
        	<array>
        		<string>\(exe)</string>
        	</array>
        	<key>RunAtLoad</key>
        	<true/>
        	<key>KeepAlive</key>
        	<true/>
        	<key>ThrottleInterval</key>
        	<integer>5</integer>
        	<key>ProcessType</key>
        	<string>Interactive</string>
        	<key>StandardOutPath</key>
        	<string>/tmp/logioptions.daemon.out.log</string>
        	<key>StandardErrorPath</key>
        	<string>/tmp/logioptions.daemon.err.log</string>
        </dict>
        </plist>
        """
        do {
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            DaemonLog.warn("LoginAgent: write plist failed \(error)")
            return false
        }
    }

    private static func unloadAndRemove() -> Bool {
        let uid = getuid()
        let domain = "gui/\(uid)"
        _ = runLaunchctl(["bootout", "\(domain)/\(label)"])
        _ = runLaunchctl(["unload", "-w", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        DaemonLog.info("LoginAgent disabled")
        return true
    }

    private static func runLaunchctl(_ args: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (-1, "\(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus, text)
    }
}
