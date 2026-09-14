// ABOUTME: Tests that notes carry tags and that tags survive the metadata sidecar round-trip.
// ABOUTME: Older sidecars without a tags field must still load.

import Testing
import Foundation
@testable import Noter

@Suite("Tags")
struct TagsTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TagsTests-\(UUID().uuidString)")
    }

    @Test("A new note has no tags")
    func defaultEmpty() {
        #expect(Note(title: "x", colorName: "mint").tags.isEmpty)
    }

    @Test("Tags round-trip through storage")
    func storageRoundTrip() throws {
        let storage = Storage(rootDirectory: tempDir())
        var note = Note(title: "Read later", colorName: "sky")
        note.tags = ["design", "swift"]
        try storage.save(note)
        #expect(try storage.load(id: note.id).tags == ["design", "swift"])
    }

    @Test("A sidecar written before tags existed still loads")
    func legacySidecarLoads() throws {
        let root = tempDir()
        let id = UUID()
        let meta = root.appendingPathComponent("metadata")
        try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
        let json = """
        {"id":"\(id.uuidString)","title":"Old","colorName":"rose","isPinned":false,
         "createdAt":"2026-01-01T00:00:00Z","modifiedAt":"2026-01-01T00:00:00Z"}
        """
        try json.write(to: meta.appendingPathComponent("\(id.uuidString).json"), atomically: true, encoding: .utf8)
        #expect(try Storage(rootDirectory: root).load(id: id).tags.isEmpty)
    }
}
