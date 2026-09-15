// ABOUTME: Tests for the cheap content questions the rail and tooltip ask of a Note.
// ABOUTME: Blankness must not require classifying the content; the excerpt must stop early.

import Foundation
import Testing
@testable import NoterKit

@Suite("Note content")
struct NoteContentTests {
    @Test("Blank means nothing but whitespace")
    func blank() {
        #expect(Note(title: "", colorName: "yellow", content: "").isBlank)
        #expect(Note(title: "", colorName: "yellow", content: " \n\t\n").isBlank)
        #expect(!Note(title: "", colorName: "yellow", content: " x ").isBlank)
    }

    @Test("Excerpt takes the first non-empty lines, trimmed, and no more")
    func excerpt() {
        let note = Note(title: "", colorName: "yellow", content: "\n  first  \n\n second\nthird\nfourth")
        #expect(note.excerpt(lines: 2) == "first\nsecond")
        #expect(Note(title: "", colorName: "yellow", content: "\n \n").excerpt(lines: 2) == "")
    }
}
