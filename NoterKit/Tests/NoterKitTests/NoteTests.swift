// ABOUTME: Tests for the Note model — Codable round-trip, default values, and equality.
// ABOUTME: Validates that notes serialize to JSON and deserialize back identically.

import Testing
import Foundation
@testable import NoterKit

@Suite("Note Model")
struct NoteTests {
    @Test("Default values are set correctly")
    func defaultValues() {
        let note = Note(title: "Test", colorName: "lavender")

        #expect(note.title == "Test")
        #expect(note.colorName == "lavender")
        #expect(note.content == "")
        #expect(note.isPinned == false)
        #expect(note.createdAt <= Date())
        #expect(note.modifiedAt <= Date())
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = Note(
            title: "Shopping List",
            colorName: "mint",
            content: "- [ ] Eggs\n- [x] Milk",
            isPinned: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Note.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.colorName == original.colorName)
        #expect(decoded.content == original.content)
        #expect(decoded.isPinned == original.isPinned)
        #expect(decoded.createdAt == original.createdAt)
        #expect(decoded.modifiedAt == original.modifiedAt)
    }

    @Test("Each note gets a unique ID")
    func uniqueIDs() {
        let a = Note(title: "A", colorName: "peach")
        let b = Note(title: "B", colorName: "sky")
        #expect(a.id != b.id)
    }

    @Test("Identifiable conformance uses id")
    func identifiable() {
        let note = Note(title: "Test", colorName: "lavender")
        let id: UUID = note.id
        #expect(id == note.id)
    }
}
