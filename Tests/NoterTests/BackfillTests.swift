// ABOUTME: Tests for which notes the launch backfill touches and what it fetches for them.
// ABOUTME: A failed favicon must not refetch the whole page every launch, and archived notes wait.

import Foundation
import Testing
@testable import Noter
@testable import NoterKit

@Suite("Backfill")
struct BackfillTests {
    private func note(preview: LinkPreview?, content: String = "https://example.com/a", archived: Bool = false) -> Note {
        Note(title: "", colorName: "yellow", content: content, isArchived: archived, preview: preview)
    }
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("A note with no preview and a link gets the full treatment")
    func full() {
        #expect(InboxWatcher.backfill(for: note(preview: nil), now: now) == .fullPreview)
    }

    @Test("A preview missing only its icon refetches the icon, not the page")
    func iconOnly() {
        let p = LinkPreview(url: URL(string: "https://example.com/a")!, title: "t", description: nil, siteName: nil, imageURL: nil, imageName: nil, faviconName: nil)
        #expect(InboxWatcher.backfill(for: note(preview: p), now: now) == .assetsOnly)
    }

    @Test("A recent attempt is not repeated; an old one is")
    func backoff() {
        var p = LinkPreview(url: URL(string: "https://example.com/a")!, title: "t", description: nil, siteName: nil, imageURL: nil, imageName: nil, faviconName: nil)
        p.assetsFetchedAt = now.addingTimeInterval(-3600)
        #expect(InboxWatcher.backfill(for: note(preview: p), now: now) == nil)
        p.assetsFetchedAt = now.addingTimeInterval(-8 * 86_400)
        #expect(InboxWatcher.backfill(for: note(preview: p), now: now) == .assetsOnly)
    }

    @Test("Complete previews, archived notes and linkless notes are left alone")
    func skipped() {
        let done = LinkPreview(url: URL(string: "https://example.com/a")!, title: "t", description: nil, siteName: nil, imageURL: nil, imageName: nil, faviconName: "f.png")
        #expect(InboxWatcher.backfill(for: note(preview: done), now: now) == nil)
        #expect(InboxWatcher.backfill(for: note(preview: nil, archived: true), now: now) == nil)
        #expect(InboxWatcher.backfill(for: note(preview: nil, content: "just words"), now: now) == nil)
    }
}
