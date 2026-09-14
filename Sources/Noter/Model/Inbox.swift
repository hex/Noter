// ABOUTME: Imports JSON drops written by the phone Shortcut into notes, then deletes the drop.
// ABOUTME: A drop carries url, title, text, raw input, and optionally a file saved beside it; notes are tagged "inbox".

import Foundation

struct InboxDrop: Codable {
    var url: String?
    var title: String?
    /// Selected text on the page, when the Shortcut could read it.
    var text: String?
    /// The raw shared input; used when there was no selection, as with a plain text share.
    var input: String?
    /// Name of a file saved beside the drop when the phone shared an image, PDF, or other file.
    var file: String?
}

struct Inbox {
    let directory: URL
    let store: NoteStore
    static let pendingTag = "inbox"

    /// Imports every readable .json drop in the directory. Unreadable drops stay for inspection.
    @discardableResult
    func importPending() throws -> [Note] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        // Shortcuts names a saved text file .txt whatever extension was asked for.
        let drops = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["json", "txt"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var imported: [Note] = []
        for file in drops {
            guard let data = try? Data(contentsOf: file),
                  let drop = try? JSONDecoder().decode(InboxDrop.self, from: data) else { continue }
            var attachment: URL?
            if let reference = drop.file, !reference.isEmpty {
                // iCloud may deliver the JSON before the file it names; wait for the next sweep.
                guard let found = resolveFile(named: reference) else { continue }
                attachment = found
            }

            var note = try store.create(title: drop.title ?? "")
            note.content = attachment == nil ? Self.content(for: drop) : Self.content(for: drop, ignoringInput: true)
            note.tags = [Self.pendingTag]
            if let attachment {
                note.attachments = [try store.attach(fileAt: attachment, to: note.id)]
            }
            try store.update(note)
            try fm.removeItem(at: file)
            imported.append(note)
        }
        return imported
    }

    /// Shortcuts names a saved file by its content type, so the reference may lack the extension.
    private func resolveFile(named reference: String) -> URL? {
        let exact = directory.appendingPathComponent(reference)
        if FileManager.default.fileExists(atPath: exact.path) { return exact }
        let candidates = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return candidates.first { $0.deletingPathExtension().lastPathComponent == reference }
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
