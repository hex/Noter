// ABOUTME: Watches the inbox folder for drops from the phone, imports them, and enriches each with Claude.
// ABOUTME: Uses a DispatchSource on the directory so iCloud Drive syncs trigger an import within a second.

import AppKit
import Foundation

@MainActor
final class InboxWatcher {
    private let inbox: Inbox
    /// Two at a time: each CLI job is a whole agent process, and imports arrive in bursts.
    private let jobs = JobQueue(limit: 2)
    private var source: DispatchSourceFileSystemObject?
    // iCloud writes the file, then finishes syncing metadata; a short wait avoids a half-written read.
    private lazy var sweepSoon = Debounce(delay: 0.5) { [weak self] in self?.importNow() }
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

    enum Backfill: Equatable { case fullPreview, assetsOnly }
    static let assetRetryInterval: TimeInterval = 7 * 86_400

    /// What a note still needs at launch, or nil. Archived notes wait until unarchived; a preview
    /// that has its icon is done; a missing icon or image is retried at most weekly.
    nonisolated static func backfill(for note: Note, now: Date = Date()) -> Backfill? {
        guard !note.isArchived else { return nil }
        guard let preview = note.preview else {
            return LinkPreview.firstURL(in: note.content) == nil ? nil : .fullPreview
        }
        guard preview.faviconName == nil || (preview.imageURL != nil && preview.imageName == nil) else { return nil }
        if let last = preview.assetsFetchedAt, now.timeIntervalSince(last) < assetRetryInterval { return nil }
        return .assetsOnly
    }

    /// Notes imported before link previews existed get one; notes whose icon or image never
    /// arrived get another try. If the body is nothing but the link, the summary is written too.
    private func backfillPreviews() {
        for note in inbox.store.notes {
            switch Self.backfill(for: note) {
            case .fullPreview:
                let bodyIsOnlyLink = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: \.isNewline).count <= 1
                if bodyIsOnlyLink { enrich(note) } else if let link = LinkPreview.firstURL(in: note.content) { attachPreview(to: note, link: link) }
            case .assetsOnly:
                fetchAssets(for: note)
            case nil:
                continue
            }
        }
    }

    private func fetchAssets(for note: Note) {
        let store = inbox.store
        Task { await jobs.submit(id: note.id, name: "assets") { [self] in
            guard var preview = note.preview else { return }
            preview = await withAssets(preview, for: note.id)
            var updated = note
            updated.preview = preview
            try? store.update(updated)
        } }
    }

    /// Downloads whatever the preview still lacks and stamps the attempt.
    private func withAssets(_ preview: LinkPreview, for noteID: UUID) async -> LinkPreview {
        var preview = preview
        if preview.imageName == nil { preview.imageName = try? await downloadImage(preview.imageURL, for: noteID) }
        if preview.faviconName == nil { preview.faviconName = try? await downloadImage(preview.faviconURL, for: noteID, suffix: "favicon") }
        preview.assetsFetchedAt = Date()
        return preview
    }

    private func attachPreview(to note: Note, link: URL) {
        let store = inbox.store
        Task { await jobs.submit(id: note.id, name: "preview") { [self] in
            do {
                let preview = await withAssets(try await LinkPreview.fetch(link), for: note.id)
                var updated = note
                updated.preview = preview
                try store.update(updated)
            } catch {
                NSLog("Noter: link preview failed for \(link): \(error)")
            }
        } }
    }

    private func sweep() { sweepSoon.trigger() }

    private func importNow() {
        guard let imported = try? inbox.importPending() else { return }
        for note in imported { enrich(note) }
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
        Task { await jobs.submit(id: note.id, name: "enrich") { [self] in
            var note = note
            if let link = LinkPreview.firstURL(in: note.content) {
                do {
                    note.preview = await withAssets(try await LinkPreview.fetch(link), for: note.id)
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
        } }
    }

    /// Saves a preview image beside the attachments; nil when there is none or it is not an image.
    private func downloadImage(_ url: URL?, for noteID: UUID, suffix: String = "preview") async throws -> String? {
        guard let url else { return nil }
        let name = "\(noteID.uuidString)-\(suffix).\(url.pathExtension.isEmpty ? "img" : url.pathExtension)"
        return try await Self.downloadImage(url, to: inbox.store.attachmentURL(name)) ? name : nil
    }

    /// Fetches, validates and writes the image off the main actor; decoding a large image there
    /// would stall the rail.
    nonisolated private static func downloadImage(_ url: URL, to destination: URL) async throws -> Bool {
        let download = try await LimitedDownload.fetch(URLRequest(url: url), limit: 8_000_000)
        guard !download.truncated, (download.response as? HTTPURLResponse)?.statusCode == 200,
              NSImage(data: download.data) != nil else { return false }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try download.data.write(to: destination)
        return true
    }
}
