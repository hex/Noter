// ABOUTME: Version and build shown in Settings > About, read from the bundle's Info.plist.
// ABOUTME: MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml are the source of truth.

import Foundation

struct AppInfo {
    let version: String
    let build: String

    /// The bundle the running binary lives in, found through the symlink `noter` is invoked by;
    /// Bundle.main would name the symlink's folder instead.
    static var executableBundle: Bundle {
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundleURL = binary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: bundleURL) ?? .main
    }

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        version = info["CFBundleShortVersionString"] as? String ?? "?"
        build = info["CFBundleVersion"] as? String ?? "?"
    }

    var label: String { "Version \(version) (\(build))" }
}
