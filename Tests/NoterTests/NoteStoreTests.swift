// ABOUTME: Tests for the in-memory note store — CRUD, ordering, and filtering.
// ABOUTME: Validates create, update, delete, recents/pinned split, and sort-by-modifiedAt.

import Testing
import Foundation
@testable import Noter

@Suite("NoteStore")
struct NoteStoreTests {
    let store: NoteStore
    let storage: Storage

    init() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("noter-store-test-\(UUID().uuidString)")
        storage = Storage(rootDirectory: tempDir)
        store = NoteStore(storage: storage)
    }

    @Test("Create adds a note and persists it")
    func createNote() throws {
        let note = try store.create(title: "First", colorName: "lavender")

        #expect(store.notes.count == 1)
        #expect(store.notes[0].id == note.id)

        let loaded = try storage.load(id: note.id)
        #expect(loaded.title == "First")
    }

    @Test("Create assigns next color when none specified")
    func createWithAutoColor() throws {
        let first = try store.create(title: "A")
        let second = try store.create(title: "B")

        #expect(first.colorName == PastelColor.allCases.first!.rawValue)
        let expectedSecond = PastelColor.allCases.first!.next.rawValue
        #expect(second.colorName == expectedSecond)
    }

    @Test("Update modifies note and persists changes")
    func updateNote() throws {
        var note = try store.create(title: "Original", colorName: "mint")
        note.content = "Updated content"
        note.title = "Changed"
        try store.update(note)

        #expect(store.notes[0].content == "Updated content")
        #expect(store.notes[0].title == "Changed")

        let loaded = try storage.load(id: note.id)
        #expect(loaded.content == "Updated content")
    }

    @Test("Delete removes note and its files")
    func deleteNote() throws {
        let note = try store.create(title: "Delete Me", colorName: "rose")
        try store.delete(id: note.id)

        #expect(store.notes.isEmpty)
        #expect(throws: StorageError.self) {
            try storage.load(id: note.id)
        }
    }

    @Test("Notes are sorted by modifiedAt descending")
    func sortOrder() throws {
        let old = try store.create(title: "Old", colorName: "lavender")
        let mid = try store.create(title: "Mid", colorName: "mint")
        let new = try store.create(title: "New", colorName: "peach")

        #expect(store.notes[0].title == "New")
        #expect(store.notes[1].title == "Mid")
        #expect(store.notes[2].title == "Old")
    }

    @Test("Updating a note moves it to the top")
    func updateBumpsToTop() throws {
        let first = try store.create(title: "First", colorName: "lavender")
        let _ = try store.create(title: "Second", colorName: "mint")

        var updated = first
        updated.content = "Edited"
        updated.modifiedAt = Date()
        try store.update(updated)

        #expect(store.notes[0].title == "First")
    }

    @Test("Pinned notes are accessible via filter")
    func pinnedFilter() throws {
        let a = try store.create(title: "Unpinned", colorName: "lavender")
        var b = try store.create(title: "Pinned", colorName: "mint")
        b.isPinned = true
        try store.update(b)

        #expect(store.pinnedNotes.count == 1)
        #expect(store.pinnedNotes[0].title == "Pinned")
        #expect(store.recentNotes.count == 1)
        #expect(store.recentNotes[0].title == "Unpinned")
    }

    @Test("Load from disk restores previously saved notes")
    func loadFromDisk() throws {
        let note = Note(title: "Persisted", colorName: "coral", content: "Saved")
        try storage.save(note)

        try store.loadFromDisk()
        #expect(store.notes.count == 1)
        #expect(store.notes[0].title == "Persisted")
        #expect(store.notes[0].content == "Saved")
    }
}
