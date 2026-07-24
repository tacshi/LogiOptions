import Foundation

enum DaemonLog {
    static func info(_ msg: String) {
        fputs("[LogiOptions] \(msg)\n", stderr)
    }

    static func warn(_ msg: String) {
        fputs("[LogiOptions] WARN \(msg)\n", stderr)
    }

    static func error(_ msg: String) {
        fputs("[LogiOptions] ERROR \(msg)\n", stderr)
    }
}
