// ABOUTME: In-memory store for notes with persistence via Storage.
// ABOUTME: Provides CRUD, sort-by-modifiedAt, and recents/pinned filtering.

import Foundation
import Observation

@Observable
public final class NoteStore {
    public private(set) var notes: [Note] = []
    private let storage: Storage
    private var nextColorIndex = 0

    public var pinnedNotes: [Note] { notes.filter { $0.isPinned && !$0.isArchived } }
    public var recentNotes: [Note] { notes.filter { !$0.isPinned && !$0.isArchived } }
    public var archivedNotes: [Note] { notes.filter(\.isArchived) }

    public init(storage: Storage) {
        self.storage = storage
    }

    // MARK: - CRUD

    @discardableResult
    public func create(title: String, colorName: String? = nil) throws -> Note {
        try add(Note(title: title, colorName: colorName ?? nextAutoColor()))
    }

    /// Saves a note built by the caller, once, complete.
    @discardableResult
    public func add(_ note: Note) throws -> Note {
        try storage.save(note)
        notes.insert(note, at: 0)
        sortNotes()
        return note
    }

    public var nextColor: String { nextAutoColor() }

    public func update(_ note: Note) throws {
        try storage.save(note)
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            // Same sort key: swap in place so the rail keeps its order and nothing else moves.
            if notes[index].modifiedAt == note.modifiedAt {
                notes[index] = note
                return
            }
            notes.remove(at: index)
        }
        notes.insert(note, at: 0)
        sortNotes()
    }

    public func delete(id: UUID) throws {
        try storage.delete(id: id)
        notes.removeAll { $0.id == id }
    }

    // MARK: - Attachments

    public func attachmentURL(_ name: String) -> URL { storage.attachmentURL(name) }

    /// Moves a file into the attachments folder under a name unique to the note; returns that name.
    public func attach(fileAt source: URL, to noteID: UUID) throws -> String {
        let name = "\(noteID.uuidString)-\(source.lastPathComponent)"
        try FileManager.default.createDirectory(at: storage.attachmentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: storage.attachmentURL(name))
        return name
    }

    // MARK: - Disk

    public func loadFromDisk() throws {
        notes = try storage.loadAll()
    }

    /// Reads the library on a background thread and publishes it; the panel appears meanwhile.
    /// Reconciles with notes another process wrote: replaces what changed, adds what is new, drops
    /// what is gone. Returns false when disk already matched, so the app's own saves change nothing.
    @discardableResult
    public func merge(fromDisk disk: [Note]) -> Bool {
        let current = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let changed = notes.count != disk.count || disk.contains { current[$0.id]?.matchesOnDisk($0) != true }
        guard changed else { return false }
        notes = disk
        sortNotes()
        return true
    }

    /// Reads the library and merges it; a failed read leaves the notes as they are.
    public func mergeFromDisk() {
        if let disk = try? storage.loadAll() { merge(fromDisk: disk) }
    }

    public func loadFromDiskInBackground() async throws {
        let storage = self.storage
        notes = try await Task.detached(priority: .userInitiated) { try storage.loadAll() }.value
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
