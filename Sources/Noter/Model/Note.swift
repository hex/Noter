// ABOUTME: Core data model for a single note.
// ABOUTME: Codable struct with UUID identity, markdown content, color, pin state, tags, and attachments.

import Foundation

struct Note: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var colorName: String
    var content: String
    var isPinned: Bool
    var tags: [String]
    /// File names under the store's attachments folder.
    var attachments: [String]
    var isArchived: Bool
    /// Preview of the first link in the body, once fetched.
    var preview: LinkPreview?
    let createdAt: Date
    var modifiedAt: Date

    /// Nothing but whitespace. Cheaper than classifying the content, which the rail must not do per dot.
    var isBlank: Bool { content.allSatisfy(\.isWhitespace) }

    /// The first `lines` non-empty lines, trimmed, stopping as soon as it has them.
    func excerpt(lines max: Int) -> String {
        var out: [Substring] = []
        for line in content.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let trimmed = line.drop(while: \.isWhitespace)
            guard !trimmed.isEmpty else { continue }
            out.append(trimmed.trimmingCharacters(in: .whitespaces)[...])
            if out.count == max { break }
        }
        return out.joined(separator: "\n")
    }

    init(
        id: UUID = UUID(),
        title: String,
        colorName: String,
        content: String = "",
        isPinned: Bool = false,
        tags: [String] = [],
        attachments: [String] = [],
        isArchived: Bool = false,
        preview: LinkPreview? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.colorName = colorName
        self.content = content
        self.isPinned = isPinned
        self.tags = tags
        self.attachments = attachments
        self.isArchived = isArchived
        self.preview = preview
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
