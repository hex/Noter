// ABOUTME: User preferences: enricher CLI, rail side, visible dot count, window level.
// ABOUTME: Backed by UserDefaults; every read falls back to the shipping default.

import Foundation
import Observation

enum RailSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
}

enum WindowLevelChoice: String, CaseIterable, Identifiable {
    /// Above the wallpaper, below every app window.
    case desktop
    /// Above app windows.
    case floating
    var id: String { rawValue }
}

@Observable
final class Settings {
    static let dotRange = 3...12

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enricherTool = Enricher.Tool(rawValue: defaults.string(forKey: Key.enricherTool) ?? "") ?? .agy
        enricherModel = defaults.string(forKey: Key.enricherModel) ?? ""
        railSide = RailSide(rawValue: defaults.string(forKey: Key.railSide) ?? "") ?? .right
        visibleDots = Self.clamp(defaults.object(forKey: Key.visibleDots) as? Int ?? 7)
        windowLevel = WindowLevelChoice(rawValue: defaults.string(forKey: Key.windowLevel) ?? "") ?? .desktop
    }

    var enricherTool: Enricher.Tool {
        didSet { defaults.set(enricherTool.rawValue, forKey: Key.enricherTool) }
    }

    /// Empty means the tool's default.
    var enricherModel: String {
        didSet { defaults.set(enricherModel, forKey: Key.enricherModel) }
    }

    var backend: Enricher.Backend {
        let model = enricherModel.trimmingCharacters(in: .whitespaces)
        return Enricher.Backend(tool: enricherTool, model: model.isEmpty ? enricherTool.defaultModel : model)
    }

    var railSide: RailSide {
        didSet { defaults.set(railSide.rawValue, forKey: Key.railSide) }
    }

    var visibleDots: Int {
        didSet {
            let clamped = Self.clamp(visibleDots)
            if clamped != visibleDots { visibleDots = clamped; return }
            defaults.set(visibleDots, forKey: Key.visibleDots)
        }
    }

    var windowLevel: WindowLevelChoice {
        didSet { defaults.set(windowLevel.rawValue, forKey: Key.windowLevel) }
    }

    private static func clamp(_ n: Int) -> Int { min(max(n, dotRange.lowerBound), dotRange.upperBound) }

    private enum Key {
        static let enricherTool = "enricherTool"
        static let enricherModel = "enricherModel"
        static let railSide = "railSide"
        static let visibleDots = "visibleDots"
        static let windowLevel = "windowLevel"
    }
}
