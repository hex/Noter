// ABOUTME: File-based persistence for notes using .md content and .json metadata sidecars.
// ABOUTME: Supports iCloud Drive container with fallback to Application Support.

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

enum StorageError: Error {
    case notFound(UUID)
    case metadataCorrupt(UUID)
}

struct Storage: Sendable {
    let rootDirectory: URL

    private var notesDirectory: URL { rootDirectory.appendingPathComponent("notes") }
    private var metadataDirectory: URL { rootDirectory.appendingPathComponent("metadata") }
    var attachmentsDirectory: URL { rootDirectory.appendingPathComponent("attachments") }

    func attachmentURL(_ name: String) -> URL { attachmentsDirectory.appendingPathComponent(name) }

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

    /// Resolves the production storage directory: iCloud container if available, else App Support.
    static func resolveRootDirectory() -> URL {
        if let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.noter.app") {
            return iCloudURL.appendingPathComponent("Documents")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Noter")
    }

    /// Where the phone Shortcut drops shared items. Shortcuts' Save File action writes into its own
    /// iCloud container, which appears in Finder as iCloud Drive/Shortcuts, so that is what is watched.
    /// Falls back next to the notes when iCloud is absent.
    static func inboxDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let shortcuts = home.appendingPathComponent("Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents")
        if FileManager.default.fileExists(atPath: shortcuts.path) {
            return shortcuts.appendingPathComponent("Noter/Inbox")
        }
        return resolveRootDirectory().appendingPathComponent("Inbox")
    }

    // MARK: - Write

    func save(_ note: Note) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)

        let contentURL = notesDirectory.appendingPathComponent("\(note.id.uuidString).md")
        try note.content.write(to: contentURL, atomically: true, encoding: .utf8)

        let metadata = NoteMetadata(from: note)
        let metadataURL = metadataDirectory.appendingPathComponent("\(note.id.uuidString).json")
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    // MARK: - Read

    func load(id: UUID) throws -> Note {
        let metadataURL = metadataDirectory.appendingPathComponent("\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw StorageError.notFound(id)
        }

        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try decoder.decode(NoteMetadata.self, from: metadataData)

        let contentURL = notesDirectory.appendingPathComponent("\(id.uuidString).md")
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

    func loadAll() throws -> [Note] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: metadataDirectory.path) else { return [] }

        let files = try fm.contentsOfDirectory(at: metadataDirectory, includingPropertiesForKeys: nil)
        let jsonFiles = files.filter { $0.pathExtension == "json" }

        var notes: [Note] = []
        for file in jsonFiles {
            let data = try Data(contentsOf: file)
            let metadata = try decoder.decode(NoteMetadata.self, from: data)
            let note = try load(id: metadata.id)
            notes.append(note)
        }

        return notes.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Delete

    func delete(id: UUID) throws {
        let fm = FileManager.default
        let contentURL = notesDirectory.appendingPathComponent("\(id.uuidString).md")
        let metadataURL = metadataDirectory.appendingPathComponent("\(id.uuidString).json")

        try? fm.removeItem(at: contentURL)
        try? fm.removeItem(at: metadataURL)
    }
}
