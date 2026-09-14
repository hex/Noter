// ABOUTME: Tests for the inbox: JSON drops from the phone become notes and the drop is consumed.
// ABOUTME: Covers a link with page text, a plain text share, and a malformed drop.

import Testing
import Foundation
@testable import Noter

@Suite("Inbox")
struct InboxTests {
    private func makeDirs() throws -> (inbox: URL, store: NoteStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InboxTests-\(UUID().uuidString)")
        let inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return (inbox, NoteStore(storage: Storage(rootDirectory: root.appendingPathComponent("Notes"))))
    }

    @Test("A shared link becomes a note with the URL and captured text, and the drop is removed")
    func linkDrop() throws {
        let (inbox, store) = try makeDirs()
        let drop = inbox.appendingPathComponent("a.json")
        try """
        {"url":"https://x.com/someone/status/1","title":"Someone on X","text":"the post body"}
        """.write(to: drop, atomically: true, encoding: .utf8)

        let imported = try Inbox(directory: inbox, store: store).importPending()

        #expect(imported.count == 1)
        #expect(imported[0].title == "Someone on X")
        #expect(imported[0].content == "https://x.com/someone/status/1\n\nthe post body")
        #expect(imported[0].tags == ["inbox"])
        #expect(store.notes.count == 1)
        #expect(!FileManager.default.fileExists(atPath: drop.path))
    }

    @Test("A plain text share becomes an untitled note, even when Shortcuts saved it as .txt")
    func textDrop() throws {
        let (inbox, store) = try makeDirs()
        try #"{"text":"call the landlord"}"#.write(to: inbox.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let imported = try Inbox(directory: inbox, store: store).importPending()

        #expect(imported[0].title == "")
        #expect(imported[0].content == "call the landlord")
    }

    @Test("When the Shortcut had no page selection, the raw input text is used")
    func inputFallback() throws {
        let (inbox, store) = try makeDirs()
        try #"{"url":"","title":"","text":"","input":"typed on the phone"}"#
            .write(to: inbox.appendingPathComponent("d.json"), atomically: true, encoding: .utf8)

        let imported = try Inbox(directory: inbox, store: store).importPending()

        #expect(imported[0].content == "typed on the phone")
    }

    @Test("A malformed drop is skipped and left in place")
    func badDrop() throws {
        let (inbox, store) = try makeDirs()
        let bad = inbox.appendingPathComponent("c.json")
        try "not json".write(to: bad, atomically: true, encoding: .utf8)

        let imported = try Inbox(directory: inbox, store: store).importPending()

        #expect(imported.isEmpty)
        #expect(store.notes.isEmpty)
        #expect(FileManager.default.fileExists(atPath: bad.path))
    }
}
