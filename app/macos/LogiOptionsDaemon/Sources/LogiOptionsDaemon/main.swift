import AppKit
import Darwin
import Foundation

// Ensure AppKit is initialized for NSWorkspace / events even as a CLI agent.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let args = CommandLine.arguments
if args.contains("--help") || args.contains("-h") {
    print("""
    LogiOptionsDaemon — background HID++ agent for LogiOptions

    Usage: LogiOptionsDaemon

    Socket: \(SocketPaths.socket)
    Config: \(SocketPaths.configFile.path)

    Stop Logi Options+ first: tools/stop_options_plus.sh
    """)
    exit(0)
}

// Single-instance lock so two helpers never fight over HID++ / the socket.
let lockPath = "/tmp/logioptions.daemon.lock"
let lockFd = open(lockPath, O_CREAT | O_RDWR, 0o644)
if lockFd >= 0 {
    if flock(lockFd, LOCK_EX | LOCK_NB) != 0 {
        DaemonLog.warn("another LogiOptionsDaemon is already running — exiting")
        exit(0)
    }
}

DaemonLog.info("LogiOptionsDaemon starting (pid \(ProcessInfo.processInfo.processIdentifier))")
Permissions.requestForDaemon()
// If the user enabled “Start at login”, re-load the LaunchAgent after a manual
// Stop (stopSession bootouts the job but keeps the plist).
LoginAgent.ensureLoadedWithCurrentBinary()
// Strong local keeps Daemon.shared (weak) alive for the process lifetime.
let daemon = Daemon()
daemon.run()