// ABOUTME: Imports JSON drops written by the phone Shortcut into notes, then deletes the drop.
// ABOUTME: A drop carries url, title, text, raw input, and optionally a file saved beside it; notes are tagged "inbox".

import Foundation

public struct InboxDrop: Codable {
    public var url: String?
    public var title: String?
    /// Selected text on the page, when the Shortcut could read it.
    public var text: String?
    /// The raw shared input; used when there was no selection, as with a plain text share.
    public var input: String?
    /// Name of a file saved beside the drop when the phone shared an image, PDF, or other file.
    public var file: String?
}

public struct Inbox {
    public let directory: URL
    public let store: NoteStore
    public static let pendingTag = "inbox"

    public init(directory: URL, store: NoteStore) {
        self.directory = directory
        self.store = store
    }

    /// Imports every readable .json drop in the directory. Unreadable drops stay for inspection.
    @discardableResult
    public func importPending() throws -> [Note] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        // Shortcuts names a saved text file .txt whatever extension was asked for.
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let drops = files
            .filter { ["json", "txt"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let attachments = Self.attachmentLookup(files)

        var imported: [Note] = []
        for file in drops {
            guard let data = try? Data(contentsOf: file),
                  let drop = try? JSONDecoder().decode(InboxDrop.self, from: data) else { continue }
            var attachment: URL?
            if let reference = drop.file, !reference.isEmpty {
                // iCloud may deliver the JSON before the file it names; wait for the next sweep.
                guard let found = attachments[reference] else { continue }
                attachment = found
            }

            var note = Note(title: drop.title ?? "", colorName: store.nextColor)
            note.content = attachment == nil ? Self.content(for: drop) : Self.content(for: drop, ignoringInput: true)
            note.tags = [Self.pendingTag]
            if let attachment {
                note.attachments = [try store.attach(fileAt: attachment, to: note.id)]
            }
            try store.add(note)
            try fm.removeItem(at: file)
            imported.append(note)
        }
        return imported
    }

    /// Shortcuts names a saved file by its content type, so a drop may reference it with or without
    /// the extension. One listing answers both, for every drop in the sweep.
    public static func attachmentLookup(_ files: [URL]) -> [String: URL] {
        var lookup: [String: URL] = [:]
        for file in files {
            lookup[file.lastPathComponent] = file
            lookup[file.deletingPathExtension().lastPathComponent] = lookup[file.deletingPathExtension().lastPathComponent] ?? file
        }
        return lookup
    }

    /// For a file share the raw input is just the file's name, which is noise in the body.
    private static func content(for drop: InboxDrop, ignoringInput: Bool = false) -> String {
        let body = drop.text.flatMap { $0.isEmpty ? nil : $0 } ?? (ignoringInput ? nil : drop.input)
        return [drop.url, body]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
