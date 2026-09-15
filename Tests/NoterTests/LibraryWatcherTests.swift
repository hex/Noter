// ABOUTME: Tests for LibraryWatcher: a note saved by another Storage on the same folder reaches the store.
// ABOUTME: Real filesystem events on a temporary library; waits past the debounce.

import Foundation
import Testing
@testable import Noter
@testable import NoterKit

@Suite("LibraryWatcher")
struct LibraryWatcherTests {
    @Test("A note written by another process appears in the store, and an edit replaces it")
    @MainActor
    func picksUpExternalWrites() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("noter-watch-\(UUID().uuidString)")
        let mine = Storage(rootDirectory: dir)
        let theirs = Storage(rootDirectory: dir)
        let store = NoteStore(storage: mine)
        try store.loadFromDisk()
        let watcher = LibraryWatcher(store: store, directory: mine.metadataDirectory)
        watcher.start()

        let note = Note(title: "Outside", colorName: "sky", content: "v1")
        try theirs.save(note)
        try await Task.sleep(for: .milliseconds(700))
        #expect(store.notes.map(\.title) == ["Outside"])

        var edited = note
        edited.content = "v2"
        edited.modifiedAt = Date()
        try theirs.save(edited)
        try await Task.sleep(for: .milliseconds(700))
        #expect(store.notes.first?.content == "v2")
    }
}
