import Foundation

/// JSONSerialization boxes numbers as NSNumber — bare `as? Double` often fails.
enum JsonUtil {
    static func double(_ any: Any?, default def: Double = 0) -> Double {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let i = any as? Int64 { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String, let d = Double(s) { return d }
        return def
    }

    static func bool(_ any: Any?, default def: Bool = false) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        if let s = any as? String {
            switch s.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: break
            }
        }
        return def
    }

    static func int(_ any: Any?, default def: Int = 0) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String, let i = Int(s) { return i }
        return def
    }
}
