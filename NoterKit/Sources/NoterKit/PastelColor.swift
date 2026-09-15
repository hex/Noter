// ABOUTME: The eight sticky-note colour names a note can carry, and the order they cycle in.
// ABOUTME: The colour values live in each app's theme; the model only knows the names.

public enum PastelColor: String, CaseIterable, Codable, Sendable {
    case lavender, mint, peach, sky, rose, lemon, coral, sage

    /// The palette entry after `name`, wrapping around; unknown names start from the first.
    public static func next(after name: String) -> PastelColor {
        let all = allCases
        guard let i = all.firstIndex(where: { $0.rawValue == name }) else { return all[0] }
        return all[(i + 1) % all.count]
    }

    public var next: PastelColor {
        let all = Self.allCases
        let index = all.firstIndex(of: self)!
        let nextIndex = all.index(after: index)
        return nextIndex == all.endIndex ? all[all.startIndex] : all[nextIndex]
    }
}
