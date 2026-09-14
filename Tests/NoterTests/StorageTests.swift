// ABOUTME: Tests for the file-based persistence layer.
// ABOUTME: Validates .md content + .json metadata round-trips using a temp directory.

import Testing
import Foundation
@testable import Noter

@Suite("Storage")
struct StorageTests {
    let storage: Storage
    let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("noter-test-\(UUID().uuidString)")
        storage = Storage(rootDirectory: tempDir)
    }

    @Test("Save and load a note round-trips content and metadata")
    func saveAndLoad() throws {
        var note = Note(title: "Test Note", colorName: "mint", content: "# Hello\n\nWorld")
        try storage.save(note)

        let loaded = try storage.load(id: note.id)
        #expect(loaded.id == note.id)
        #expect(loaded.title == "Test Note")
        #expect(loaded.colorName == "mint")
        #expect(loaded.content == "# Hello\n\nWorld")
        #expect(loaded.isPinned == false)
    }

    @Test("Content is stored as plain .md file")
    func contentIsMarkdown() throws {
        let note = Note(title: "MD Test", colorName: "peach", content: "- [ ] Buy eggs")
        try storage.save(note)

        let mdURL = tempDir.appendingPathComponent("notes/\(note.id.uuidString).md")
        let content = try String(contentsOf: mdURL, encoding: .utf8)
        #expect(content == "- [ ] Buy eggs")
    }

    @Test("Metadata is stored as JSON sidecar")
    func metadataIsJSON() throws {
        let note = Note(title: "JSON Test", colorName: "sky", isPinned: true)
        try storage.save(note)

        let jsonURL = tempDir.appendingPathComponent("metadata/\(note.id.uuidString).json")
        let data = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NoteMetadata.self, from: data)
        #expect(decoded.id == note.id)
        #expect(decoded.title == "JSON Test")
        #expect(decoded.colorName == "sky")
        #expect(decoded.isPinned == true)
    }

    @Test("Delete removes both .md and .json files")
    func deleteRemovesFiles() throws {
        let note = Note(title: "Delete Me", colorName: "rose")
        try storage.save(note)
        try storage.delete(id: note.id)

        let mdURL = tempDir.appendingPathComponent("notes/\(note.id.uuidString).md")
        let jsonURL = tempDir.appendingPathComponent("metadata/\(note.id.uuidString).json")
        #expect(!FileManager.default.fileExists(atPath: mdURL.path))
        #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
    }

    @Test("Load all returns all saved notes sorted by modifiedAt descending")
    func loadAll() throws {
        let older = Note(
            title: "Older",
            colorName: "lavender",
            modifiedAt: Date(timeIntervalSince1970: 1000)
        )
        let newer = Note(
            title: "Newer",
            colorName: "mint",
            modifiedAt: Date(timeIntervalSince1970: 2000)
        )
        try storage.save(older)
        try storage.save(newer)

        let all = try storage.loadAll()
        #expect(all.count == 2)
        #expect(all[0].title == "Newer")
        #expect(all[1].title == "Older")
    }

    @Test("Load non-existent note throws")
    func loadNonExistent() {
        #expect(throws: StorageError.self) {
            try storage.load(id: UUID())
        }
    }

    @Test("Save updates existing note without creating duplicates")
    func saveUpdatesExisting() throws {
        var note = Note(title: "Original", colorName: "coral", content: "v1")
        try storage.save(note)

        note.content = "v2"
        note.title = "Updated"
        try storage.save(note)

        let loaded = try storage.load(id: note.id)
        #expect(loaded.content == "v2")
        #expect(loaded.title == "Updated")

        let all = try storage.loadAll()
        #expect(all.count == 1)
    }
}

@Suite("Storage writes")
struct StorageWriteTests {
    @Test("A metadata-only save leaves the content file untouched")
    func skipsUnchangedContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StorageWrite-\(UUID().uuidString)")
        let storage = Storage(rootDirectory: root)
        var note = Note(title: "A", colorName: "yellow", content: "body")
        try storage.save(note)
        let md = root.appendingPathComponent("notes/\(note.id.uuidString).md")
        let before = try FileManager.default.attributesOfItem(atPath: md.path)[.modificationDate] as! Date
        Thread.sleep(forTimeInterval: 0.05)
        note.title = "B"
        try storage.save(note)
        let after = try FileManager.default.attributesOfItem(atPath: md.path)[.modificationDate] as! Date
        #expect(before == after)
        #expect(try storage.load(id: note.id).title == "B")
    }
}
