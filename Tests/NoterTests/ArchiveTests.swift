// ABOUTME: Tests for archiving: archived notes leave the rail lists but stay on disk and can come back.
// ABOUTME: Also checks the sidecar round-trip of the archived flag and the preview.

import Testing
import Foundation
@testable import Noter

@Suite("Archive")
struct ArchiveTests {
    private func store() -> NoteStore {
        NoteStore(storage: Storage(rootDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveTests-\(UUID().uuidString)")))
    }

    @Test("Archived notes are excluded from pinned and recent, listed separately")
    func lists() throws {
        let s = store()
        let a = try s.create(title: "A")
        var b = try s.create(title: "B")
        b.isArchived = true
        try s.update(b)
        #expect(s.recentNotes.map(\.id) == [a.id])
        #expect(s.archivedNotes.map(\.id) == [b.id])
    }

    @Test("Archived flag and link preview survive storage")
    func roundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveTests-\(UUID().uuidString)")
        let storage = Storage(rootDirectory: root)
        var n = Note(title: "x", colorName: "sky")
        n.isArchived = true
        n.preview = LinkPreview(url: URL(string: "https://x.com/a/status/1")!, title: "Author", description: "tweet", siteName: "X", imageURL: nil, imageName: "img.jpg", faviconName: "fav.png")
        try storage.save(n)
        let back = try storage.load(id: n.id)
        #expect(back.isArchived)
        #expect(back.preview?.title == "Author")
        #expect(back.preview?.imageName == "img.jpg")
        #expect(back.preview?.faviconName == "fav.png")
        #expect(n.preview?.faviconURL?.absoluteString == "https://www.google.com/s2/favicons?domain=x.com&sz=64")
    }
}
