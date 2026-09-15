// ABOUTME: Tests for NoteKind, the content classifier that picks a badge icon.
// ABOUTME: Each case is a literal note body and the kind a reader would expect.

import Testing
import Foundation
@testable import Noter
@testable import NoterKit

@Suite("Note Kind")
struct NoteKindTests {
    @Test("Empty and whitespace-only are empty")
    func empty() {
        #expect(NoteKind.classify("") == .empty)
        #expect(NoteKind.classify("  \n\n ") == .empty)
    }

    @Test("Plain prose is text")
    func text() {
        #expect(NoteKind.classify("Call Dana about the lease on Thursday.") == .text)
    }

    @Test("A note containing a URL is a link to that URL")
    func link() {
        let kind = NoteKind.classify("read later\nhttps://developer.apple.com/documentation/swiftui and more")
        #expect(kind == .link(URL(string: "https://developer.apple.com/documentation/swiftui")!))
    }

    @Test("Markdown task items make a checklist")
    func checklist() {
        #expect(NoteKind.classify("- [ ] oat milk\n- [x] lemons") == .checklist)
    }

    @Test("A code fence makes code, even with a link inside")
    func code() {
        #expect(NoteKind.classify("```swift\nlet u = URL(string: \"https://a.b\")\n```") == .code)
    }

    @Test("Favicon URL points at the link's host")
    func favicon() {
        let kind = NoteKind.link(URL(string: "https://github.com/apple/swift-markdown")!)
        #expect(kind.faviconURL?.absoluteString == "https://www.google.com/s2/favicons?domain=github.com&sz=64")
        #expect(NoteKind.checklist.faviconURL == nil)
    }
}
