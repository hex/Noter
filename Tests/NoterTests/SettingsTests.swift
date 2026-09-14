// ABOUTME: Tests for Settings, the user preferences stored in UserDefaults.
// ABOUTME: Uses a throwaway suite so nothing leaks into the real defaults.

import Foundation
import Testing
@testable import Noter

@Suite("Settings")
struct SettingsTests {
    private func fresh() -> UserDefaults {
        let name = "SettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Defaults: agy backend, right rail, seven dots, desktop level")
    func defaults() {
        let settings = Settings(defaults: fresh())
        #expect(settings.enricherTool == .agy)
        #expect(settings.backend == Enricher.Backend(tool: .agy, model: "gemini-3.8-flash"))
        #expect(settings.railSide == .right)
        #expect(settings.visibleDots == 7)
        #expect(settings.windowLevel == .desktop)
    }

    @Test("Changes survive a reload from the same defaults")
    func roundTrip() {
        let defaults = fresh()
        let settings = Settings(defaults: defaults)
        settings.enricherTool = .codex
        settings.enricherModel = "gpt-6-astra"
        settings.railSide = .left
        settings.visibleDots = 10
        settings.windowLevel = .floating

        let reloaded = Settings(defaults: defaults)
        #expect(reloaded.backend == Enricher.Backend(tool: .codex, model: "gpt-6-astra"))
        #expect(reloaded.railSide == .left)
        #expect(reloaded.visibleDots == 10)
        #expect(reloaded.windowLevel == .floating)
    }

    @Test("An empty model falls back to the tool's default")
    func modelFallback() {
        let settings = Settings(defaults: fresh())
        settings.enricherTool = .claude
        settings.enricherModel = ""
        #expect(settings.backend.model == Enricher.Tool.claude.defaultModel)
    }

    @Test("Visible dots are clamped to 3...12")
    func clamped() {
        let settings = Settings(defaults: fresh())
        settings.visibleDots = 1
        #expect(settings.visibleDots == 3)
        settings.visibleDots = 40
        #expect(settings.visibleDots == 12)
    }

    @Test("The clamped value is what gets stored")
    func clampPersists() {
        let defaults = fresh()
        Settings(defaults: defaults).visibleDots = 40
        #expect(Settings(defaults: defaults).visibleDots == 12)
    }
}
