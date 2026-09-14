// ABOUTME: Classifies a note's content so the rail badge can show a fitting icon.
// ABOUTME: Code fence beats checklist beats link; prose and empty notes show color only.

import Foundation

enum NoteKind: Equatable {
    case empty
    case text
    case link(URL)
    case checklist
    case code

    static func classify(_ content: String) -> NoteKind {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.contains("```") { return .code }
        if trimmed.range(of: #"(?m)^\s*[-*]\s\[[ xX]\]"#, options: .regularExpression) != nil {
            return .checklist
        }
        if let url = firstURL(in: trimmed) { return .link(url) }
        return .text
    }

    /// SF Symbol for kinds without a favicon; nil means the badge is color only.
    var symbolName: String? {
        switch self {
        case .checklist: "checklist"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        case .empty, .text: nil
        }
    }

    var faviconURL: URL? {
        guard case .link(let url) = self, let host = url.host() else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }

    private static func firstURL(in text: String) -> URL? { LinkPreview.firstURL(in: text) }
}
