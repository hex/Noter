// ABOUTME: Tests for the one-time copy of an Application Support library into the iCloud container.
// ABOUTME: Uses two temporary folders; no iCloud.
import Testing
import Foundation
@testable import NoterKit

@Suite("Migration")
struct MigrationTests {
    @Test("A legacy library is copied once, and the copy is not repeated")
    func copiesOnce() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("noter-migrate-\(UUID().uuidString)")
        let legacy = base.appendingPathComponent("legacy"), root = base.appendingPathComponent("container")
        let old = Storage(rootDirectory: legacy)
        let note = Note(title: "Old", colorName: "sky", content: "body")
        try old.save(note)
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        try Data("img".utf8).write(to: legacy.appendingPathComponent("attachments/a.png"))

        #expect(try Storage.migrate(from: legacy, to: root) == true)
        let new = Storage(rootDirectory: root)
        #expect(try new.load(id: note.id).content == "body")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("attachments/a.png").path))
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("metadata/\(note.id.uuidString).json").path))

        try old.save(Note(title: "Later", colorName: "sky"))
        #expect(try Storage.migrate(from: legacy, to: root) == false)
        #expect(try new.loadAll().count == 1)
    }

    @Test("Nothing to migrate when the legacy folder is missing or the container already has notes")
    func skips() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("noter-migrate-\(UUID().uuidString)")
        let legacy = base.appendingPathComponent("legacy"), root = base.appendingPathComponent("container")
        #expect(try Storage.migrate(from: legacy, to: root) == false)
        try Storage(rootDirectory: root).save(Note(title: "Cloud", colorName: "sky"))
        try Storage(rootDirectory: legacy).save(Note(title: "Old", colorName: "sky"))
        #expect(try Storage.migrate(from: legacy, to: root) == false)
    }

    @Test("Folders the app already created in the container are filled, not replaced")
    func fillsExistingFolders() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("noter-migrate-\(UUID().uuidString)")
        let legacy = base.appendingPathComponent("legacy"), root = base.appendingPathComponent("container")
        let note = Note(title: "Old", colorName: "sky", content: "body")
        try Storage(rootDirectory: legacy).save(note)
        let metadata = root.appendingPathComponent("metadata")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let inodeBefore = try FileManager.default.attributesOfItem(atPath: metadata.path)[.systemFileNumber] as? Int

        #expect(try Storage.migrate(from: legacy, to: root) == true)
        #expect(try Storage(rootDirectory: root).load(id: note.id).content == "body")
        let inodeAfter = try FileManager.default.attributesOfItem(atPath: metadata.path)[.systemFileNumber] as? Int
        #expect(inodeBefore != nil && inodeBefore == inodeAfter)
    }
}
