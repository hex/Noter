// ABOUTME: Tests for AppInfo, the version strings shown in Settings > About.
// ABOUTME: Checks the Info.plist keys are read and that a missing key does not blank the label.

import Testing
@testable import Noter

@Suite("App info")
struct AppInfoTests {
    @Test("Version and build come from the bundle's Info.plist")
    func fromInfo() {
        let info = AppInfo(info: ["CFBundleShortVersionString": "2026.9.0", "CFBundleVersion": "2026091401"])
        #expect(info.version == "2026.9.0")
        #expect(info.build == "2026091401")
        #expect(info.label == "Version 2026.9.0 (2026091401)")
    }

    @Test("Missing keys read as unknown rather than empty")
    func missing() {
        let info = AppInfo(info: [:])
        #expect(info.label == "Version ? (?)")
    }
}
