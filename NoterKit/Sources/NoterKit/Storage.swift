// ABOUTME: File-based persistence for notes using .md content and .json metadata sidecars.
// ABOUTME: Lives in the app's iCloud container, falling back to Application Support, and copies an older library in once.

import Foundation

/// Metadata sidecar stored alongside each note's .md content file.
struct NoteMetadata: Codable, Sendable {
    let id: UUID
    var title: String
    var colorName: String
    var isPinned: Bool
    var tags: [String]
    var attachments: [String]
    var isArchived: Bool
    var preview: LinkPreview?
    let createdAt: Date
    var modifiedAt: Date

    init(from note: Note) {
        self.id = note.id
        self.title = note.title
        self.colorName = note.colorName
        self.isPinned = note.isPinned
        self.tags = note.tags
        self.attachments = note.attachments
        self.isArchived = note.isArchived
        self.preview = note.preview
        self.createdAt = note.createdAt
        self.modifiedAt = note.modifiedAt
    }

    /// Sidecars written before tags or attachments existed lack those keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        colorName = try c.decode(String.self, forKey: .colorName)
        isPinned = try c.decode(Bool.self, forKey: .isPinned)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        attachments = try c.decodeIfPresent([String].self, forKey: .attachments) ?? []
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        preview = try c.decodeIfPresent(LinkPreview.self, forKey: .preview)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
    }
}

public enum StorageError: Error {
    case notFound(UUID)
    case metadataCorrupt(UUID)
}

public struct Storage: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) { self.rootDirectory = rootDirectory }

    private var notesDirectory: URL { rootDirectory.appendingPathComponent("notes") }
    public var metadataDirectory: URL { rootDirectory.appendingPathComponent("metadata") }
    public var attachmentsDirectory: URL { rootDirectory.appendingPathComponent("attachments") }

    public func attachmentURL(_ name: String) -> URL { attachmentsDirectory.appendingPathComponent(name) }

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    public static let containerID = "iCloud.com.hexul.noter"
    static let migrationMarker = "migrated-from-app-support"

    /// The iCloud container when the account and entitlement allow it, else Application Support.
    public static func resolveRootDirectory(fileManager: FileManager = .default) -> URL {
        if let container = fileManager.url(forUbiquityContainerIdentifier: containerID) {
            return container.appendingPathComponent("Documents")
        }
        return legacyRootDirectory(fileManager: fileManager)
    }

    /// Where the library lived before it moved into the iCloud container.
    public static func legacyRootDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Noter")
    }

    /// Copies notes, metadata and attachments from `legacy` into `root` once, marked by a file in `root`.
    /// Skipped when `root` already holds notes. Returns true when it copied.
    @discardableResult
    public static func migrate(from legacy: URL, to root: URL, fileManager: FileManager = .default) throws -> Bool {
        let marker = root.appendingPathComponent(migrationMarker)
        guard legacy != root, !fileManager.fileExists(atPath: marker.path),
              fileManager.fileExists(atPath: legacy.appendingPathComponent("metadata").path),
              try Storage(rootDirectory: root).loadAll().isEmpty else { return false }
        // Files are copied one by one into folders that may already exist: the app watches
        // `metadata` from launch, and replacing the folder would leave it watching a deleted inode.
        for folder in ["notes", "metadata", "attachments"] {
            let src = legacy.appendingPathComponent(folder), dst = root.appendingPathComponent(folder)
            guard fileManager.fileExists(atPath: src.path) else { continue }
            try fileManager.createDirectory(at: dst, withIntermediateDirectories: true)
            for name in try fileManager.contentsOfDirectory(atPath: src.path) {
                let target = dst.appendingPathComponent(name)
                if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
                try fileManager.copyItem(at: src.appendingPathComponent(name), to: target)
            }
        }
        try Data(ISO8601DateFormatter().string(from: Date()).utf8).write(to: marker)
        return true
    }

    /// Where the phone Shortcut drops shared items. Shortcuts' Save File action writes into its own
    /// iCloud container, which appears in Finder as iCloud Drive/Shortcuts, so that is what is watched.
    /// Falls back next to the notes when iCloud is absent.
    public static func inboxDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let shortcuts = home.appendingPathComponent("Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents")
        if FileManager.default.fileExists(atPath: shortcuts.path) {
            return shortcuts.appendingPathComponent("Noter/Inbox")
        }
        return resolveRootDirectory().appendingPathComponent("Inbox")
    }

    // MARK: - Write

    public func save(_ note: Note) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)

        // Most saves change only metadata (tags, pin, preview); rewriting the body would also
        // make iCloud sync it again for nothing.
        let contentURL = notesDirectory.appendingPathComponent("\(note.id.uuidString).md")
        if (try? String(contentsOf: contentURL, encoding: .utf8)) != note.content {
            try note.content.write(to: contentURL, atomically: true, encoding: .utf8)
        }

        let metadata = NoteMetadata(from: note)
        let metadataURL = metadataDirectory.appendingPathComponent("\(note.id.uuidString).json")
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    // MARK: - Read

    public func load(id: UUID) throws -> Note {
        let metadataURL = metadataDirectory.appendingPathComponent("\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw StorageError.notFound(id)
        }

        let metadataData = try Data(contentsOf: metadataURL)
        return note(from: try decoder.decode(NoteMetadata.self, from: metadataData))
    }

    private func note(from metadata: NoteMetadata) -> Note {
        let contentURL = notesDirectory.appendingPathComponent("\(metadata.id.uuidString).md")
        let content = (try? String(contentsOf: contentURL, encoding: .utf8)) ?? ""
        return Note(
            id: metadata.id,
            title: metadata.title,
            colorName: metadata.colorName,
            content: content,
            isPinned: metadata.isPinned,
            tags: metadata.tags,
            attachments: metadata.attachments,
            isArchived: metadata.isArchived,
            preview: metadata.preview,
            createdAt: metadata.createdAt,
            modifiedAt: metadata.modifiedAt
        )
    }

    public func loadAll() throws -> [Note] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: metadataDirectory.path) else { return [] }

        let files = try fm.contentsOfDirectory(at: metadataDirectory, includingPropertiesForKeys: nil)
        let jsonFiles = files.filter { $0.pathExtension == "json" }

        var notes: [Note] = []
        for file in jsonFiles {
            let data = try Data(contentsOf: file)
            notes.append(note(from: try decoder.decode(NoteMetadata.self, from: data)))
        }

        return notes.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Delete

    public func delete(id: UUID) throws {
        let fm = FileManager.default
        let contentURL = notesDirectory.appendingPathComponent("\(id.uuidString).md")
        let metadataURL = metadataDirectory.appendingPathComponent("\(id.uuidString).json")

        try? fm.removeItem(at: contentURL)
        try? fm.removeItem(at: metadataURL)
    }
}
