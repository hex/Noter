// ABOUTME: Version and build shown in Settings > About, read from the bundle's Info.plist.
// ABOUTME: MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml are the source of truth.

import Foundation

struct AppInfo {
    let version: String
    let build: String

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        version = info["CFBundleShortVersionString"] as? String ?? "?"
        build = info["CFBundleVersion"] as? String ?? "?"
    }

    var label: String { "Version \(version) (\(build))" }
}
