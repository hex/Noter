// ABOUTME: Watches the metadata folder so notes written by the noter CLI or another process appear in the app.
// ABOUTME: A DispatchSource on the directory fires on every atomic rename; the store merges what changed.

import Foundation
import NoterKit

@MainActor
final class LibraryWatcher {
    private let store: NoteStore
    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    // A CLI edit writes the body then the sidecar; a short wait reads both together.
    private lazy var reloadSoon = Debounce(delay: 0.3) { [weak self] in self?.reload() }

    init(store: NoteStore, directory: URL) {
        self.store = store
        self.directory = directory
    }

    func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in self?.reloadSoon.trigger() }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        self.source = source
    }

    private func reload() {
        store.mergeFromDisk()
    }
}
