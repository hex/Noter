// ABOUTME: Core data model for a single note.
// ABOUTME: Codable struct with UUID identity, markdown content, color, pin state, tags, and attachments.

import Foundation

public struct Note: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var colorName: String
    public var content: String
    public var isPinned: Bool
    public var tags: [String]
    /// File names under the store's attachments folder.
    public var attachments: [String]
    public var isArchived: Bool
    /// Preview of the first link in the body, once fetched.
    public var preview: LinkPreview?
    public let createdAt: Date
    public var modifiedAt: Date

    /// Equal as far as the sidecar can tell: dates are stored to the second, so a note read back
    /// from disk differs from the one that was saved only in sub-second digits.
    public func matchesOnDisk(_ other: Note) -> Bool {
        func seconds(_ d: Date) -> TimeInterval { d.timeIntervalSince1970.rounded(.down) }
        return id == other.id && title == other.title && colorName == other.colorName
            && content == other.content && isPinned == other.isPinned && tags == other.tags
            && attachments == other.attachments && isArchived == other.isArchived
            && preview?.withWholeSecondDates == other.preview?.withWholeSecondDates
            && seconds(createdAt) == seconds(other.createdAt) && seconds(modifiedAt) == seconds(other.modifiedAt)
    }

    /// Nothing but whitespace. Cheaper than classifying the content, which the rail must not do per dot.
    public var isBlank: Bool { content.allSatisfy(\.isWhitespace) }

    /// The first `lines` non-empty lines, trimmed, stopping as soon as it has them.
    public func excerpt(lines max: Int) -> String {
        var out: [Substring] = []
        for line in content.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let trimmed = line.drop(while: \.isWhitespace)
            guard !trimmed.isEmpty else { continue }
            out.append(trimmed.trimmingCharacters(in: .whitespaces)[...])
            if out.count == max { break }
        }
        return out.joined(separator: "\n")
    }

    public init(
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
