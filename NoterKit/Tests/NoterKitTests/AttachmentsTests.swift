// ABOUTME: Tests for note attachments: the sidecar carries file names and the store resolves them to URLs.
// ABOUTME: Also covers importing an inbox drop that references a file shared from the phone.

import Testing
import Foundation
@testable import NoterKit

@Suite("Attachments")
struct AttachmentsTests {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AttachmentsTests-\(UUID().uuidString)")
    }

    @Test("Attachment names round-trip through storage and resolve under the attachments folder")
    func roundTrip() throws {
        let root = root()
        let storage = Storage(rootDirectory: root)
        var note = Note(title: "Receipt", colorName: "lemon")
        note.attachments = ["abc-receipt.jpg"]
        try storage.save(note)
        #expect(try storage.load(id: note.id).attachments == ["abc-receipt.jpg"])
        #expect(storage.attachmentURL("abc-receipt.jpg") == root.appendingPathComponent("attachments/abc-receipt.jpg"))
    }

    @Test("A drop with a file moves the file into attachments and references it from the note")
    func fileDrop() throws {
        let root = root()
        let inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let store = NoteStore(storage: Storage(rootDirectory: root.appendingPathComponent("Notes")))
        try Data([0xFF, 0xD8, 0xFF]).write(to: inbox.appendingPathComponent("20260914-1200-IMG_1.jpg"))
        try #"{"file":"20260914-1200-IMG_1.jpg","title":"IMG_1","text":"","input":""}"#
            .write(to: inbox.appendingPathComponent("20260914-1200.json"), atomically: true, encoding: .utf8)

        let imported = try Inbox(directory: inbox, store: store).importPending()

        #expect(imported.count == 1)
        #expect(imported[0].attachments == ["\(imported[0].id.uuidString)-20260914-1200-IMG_1.jpg"])
        #expect(imported[0].content == "")
        let moved = store.attachmentURL(imported[0].attachments[0])
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(!FileManager.default.fileExists(atPath: inbox.appendingPathComponent("20260914-1200-IMG_1.jpg").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.path).isEmpty)
    }

    @Test("A file reference without its extension still finds the saved file")
    func extensionlessReference() throws {
        let root = root()
        let inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let store = NoteStore(storage: Storage(rootDirectory: root.appendingPathComponent("Notes")))
        try Data([1, 2, 3]).write(to: inbox.appendingPathComponent("20260914-1533-desk.png"))
        try #"{"file":"20260914-1533-desk","input":"desk"}"#
            .write(to: inbox.appendingPathComponent("20260914-1535.txt"), atomically: true, encoding: .utf8)

        let imported = try Inbox(directory: inbox, store: store).importPending()

        #expect(imported.count == 1)
        #expect(imported[0].attachments.first?.hasSuffix("20260914-1533-desk.png") == true)
        #expect(imported[0].content == "")
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.path).isEmpty)
    }

    @Test("A drop whose file has not synced yet is left for the next sweep")
    func fileNotYetSynced() throws {
        let root = root()
        let inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let store = NoteStore(storage: Storage(rootDirectory: root.appendingPathComponent("Notes")))
        let drop = inbox.appendingPathComponent("a.json")
        try #"{"file":"missing.pdf"}"#.write(to: drop, atomically: true, encoding: .utf8)

        let imported = try Inbox(directory: inbox, store: store).importPending()

        #expect(imported.isEmpty)
        #expect(FileManager.default.fileExists(atPath: drop.path))
    }
}
