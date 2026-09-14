// ABOUTME: Watches the inbox folder for drops from the phone, imports them, and enriches each with Claude.
// ABOUTME: Uses a DispatchSource on the directory so iCloud Drive syncs trigger an import within a second.

import AppKit
import Foundation

@MainActor
final class InboxWatcher {
    private let inbox: Inbox
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init(inbox: Inbox) {
        self.inbox = inbox
    }

    /// Creates the folder if needed, imports anything already waiting, then watches for new drops.
    func start() {
        try? FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true)
        fd = open(inbox.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in self?.sweep() }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        self.source = source
        sweep()
        backfillPreviews()
    }

    /// Notes imported before link previews existed: fetch their preview, and if the body is nothing
    /// but the link, write the summary they never got.
    private func backfillPreviews() {
        for note in inbox.store.notes where note.preview?.faviconName == nil {
            // The link is in the body until a preview exists; after that only the preview holds it.
            guard let link = note.preview?.url ?? LinkPreview.firstURL(in: note.content) else { continue }
            let bodyIsOnlyLink = note.preview == nil && note.content.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isNewline).count <= 1
            if bodyIsOnlyLink {
                enrich(note)
            } else {
                attachPreview(to: note, link: link)
            }
        }
    }

    private func attachPreview(to note: Note, link: URL) {
        let store = inbox.store
        Task {
            do {
                var preview = try await LinkPreview.fetch(link)
                preview.imageName = try? await downloadImage(preview.imageURL, for: note.id)
                preview.faviconName = try? await downloadImage(preview.faviconURL, for: note.id, suffix: "favicon")
                var updated = note
                updated.preview = preview
                try store.update(updated)
            } catch {
                NSLog("Noter: link preview failed for \(link): \(error)")
            }
        }
    }

    private func sweep() {
        // iCloud writes the file, then finishes syncing metadata; a short delay avoids a half-written read.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let imported = try? self.inbox.importPending() else { return }
            for note in imported { self.enrich(note) }
        }
    }

    /// Runs the model again on the note as it stands; the rail pulses while it works.
    func rerun(_ note: Note) {
        var pending = note
        pending.tags = [Inbox.pendingTag]
        try? inbox.store.update(pending)
        enrich(pending)
    }

    private func enrich(_ note: Note) {
        let store = inbox.store
        Task {
            var note = note
            if let link = LinkPreview.firstURL(in: note.content) {
                do {
                    var preview = try await LinkPreview.fetch(link)
                    preview.imageName = try? await downloadImage(preview.imageURL, for: note.id)
                    preview.faviconName = try? await downloadImage(preview.faviconURL, for: note.id, suffix: "favicon")
                    note.preview = preview
                    try store.update(note)
                } catch {
                    NSLog("Noter: link preview failed for \(link): \(error)")
                }
            }
            do {
                let enriched = try await Enricher.enrich(note, attachments: note.attachments.map(store.attachmentURL))
                try store.update(enriched)
            } catch {
                NSLog("Noter: enrichment failed for \(note.id): \(error)")
            }
        }
    }

    /// Saves a preview image beside the attachments; nil when there is none or it is not an image.
    private func downloadImage(_ url: URL?, for noteID: UUID, suffix: String = "preview") async throws -> String? {
        guard let url else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8_000_000,
              NSImage(data: data) != nil else { return nil }
        let name = "\(noteID.uuidString)-\(suffix).\(url.pathExtension.isEmpty ? "img" : url.pathExtension)"
        try FileManager.default.createDirectory(at: inbox.store.attachmentURL(name).deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: inbox.store.attachmentURL(name))
        return name
    }
}
