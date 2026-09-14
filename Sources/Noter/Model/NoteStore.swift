// ABOUTME: In-memory store for notes with persistence via Storage.
// ABOUTME: Provides CRUD, sort-by-modifiedAt, and recents/pinned filtering.

import Foundation
import Observation

@Observable
final class NoteStore {
    private(set) var notes: [Note] = []
    private let storage: Storage
    private var nextColorIndex = 0

    var pinnedNotes: [Note] { notes.filter { $0.isPinned && !$0.isArchived } }
    var recentNotes: [Note] { notes.filter { !$0.isPinned && !$0.isArchived } }
    var archivedNotes: [Note] { notes.filter(\.isArchived) }

    init(storage: Storage) {
        self.storage = storage
    }

    // MARK: - CRUD

    @discardableResult
    func create(title: String, colorName: String? = nil) throws -> Note {
        let color = colorName ?? nextAutoColor()
        let note = Note(title: title, colorName: color)
        try storage.save(note)
        notes.insert(note, at: 0)
        return note
    }

    func update(_ note: Note) throws {
        try storage.save(note)
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes.remove(at: index)
        }
        notes.insert(note, at: 0)
        sortNotes()
    }

    func delete(id: UUID) throws {
        try storage.delete(id: id)
        notes.removeAll { $0.id == id }
    }

    // MARK: - Attachments

    func attachmentURL(_ name: String) -> URL { storage.attachmentURL(name) }

    /// Moves a file into the attachments folder under a name unique to the note; returns that name.
    func attach(fileAt source: URL, to noteID: UUID) throws -> String {
        let name = "\(noteID.uuidString)-\(source.lastPathComponent)"
        try FileManager.default.createDirectory(at: storage.attachmentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: storage.attachmentURL(name))
        return name
    }

    // MARK: - Disk

    func loadFromDisk() throws {
        notes = try storage.loadAll()
    }

    // MARK: - Private

    private func sortNotes() {
        notes.sort { $0.modifiedAt > $1.modifiedAt }
    }

    private func nextAutoColor() -> String {
        let all = PastelColor.allCases
        let color = all[nextColorIndex % all.count]
        nextColorIndex += 1
        return color.rawValue
    }
}
