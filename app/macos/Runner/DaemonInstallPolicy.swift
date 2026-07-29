import Foundation

enum DaemonInstallPolicy {
  static let handledVersionKey = "com.logioptions.daemonHandledVersion"

  static func versionIdentifier(bundle: Bundle = .main) -> String {
    let version =
      bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "0"
    let build =
      bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
      ?? "0"
    return "\(version)+\(build)"
  }

  static func shouldTransition(
    currentVersion: String,
    lastHandledVersion: String?
  ) -> Bool {
    currentVersion != lastHandledVersion
  }
}
