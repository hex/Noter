// ABOUTME: The noter command line: list, show, add, edit, archive, unarchive, delete against the library on disk.
// ABOUTME: Prints JSON so agents can parse it; every write bumps modifiedAt so the running app picks it up.

import Foundation
import NoterKit

enum CLI {
    struct Result: Equatable {
        var stdout = ""
        var stderr = ""
        var exitCode: Int32 = 0
    }

    static let usage = """
    noter — read and write Noter notes from the shell. Output is JSON; ids may be abbreviated to a unique prefix.

      noter list [--archived | --all]                 notes, newest first (default: active only)
      noter show <id>                                 one note with its body
      noter add [--title T] [--tags a,b] [--color C] [--pin] [TEXT | -]
                                                      new note; TEXT is the body, "-" reads it from stdin
      noter edit <id> [--title T] [--content TEXT | --content -] [--tags a,b] [--color C] [--pin | --unpin]
                                                      change only the fields given
      noter archive <id> | unarchive <id> | delete <id>
      noter mcp                                       serve the same verbs as MCP tools over stdio

    Colours: \(PastelColor.allCases.map(\.rawValue).joined(separator: ", "))
    """

    static func run(arguments: [String], storage: Storage, stdin: String) -> Result {
        var result = Result()
        do {
            result.stdout = try execute(arguments, storage: storage, stdin: stdin)
        } catch {
            result.stderr = "noter: \(error.localizedDescription)\n"
            result.exitCode = 1
        }
        return result
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func execute(_ arguments: [String], storage: Storage, stdin: String) throws -> String {
        var args = arguments
        guard let verb = args.first, verb != "--help", verb != "-h" else { return usage + "\n" }
        args.removeFirst()
        var options = Options(args)
        switch verb {
        case "list":
            let notes = try storage.loadAll()
            let shown: [Note]
            if options.flag("--all") { shown = notes }
            else if options.flag("--archived") { shown = notes.filter(\.isArchived) }
            else { shown = notes.filter { !$0.isArchived } }
            try options.finish()
            return try encode(shown.map { summary($0) })
        case "show":
            let note = try find(try options.positional("id"), in: storage)
            try options.finish()
            return try encode(full(note))
        case "add":
            var note = Note(title: options.value("--title") ?? "Untitled", colorName: try color(options.value("--color")) ?? PastelColor.allCases[0].rawValue)
            if let tags = options.value("--tags") { note.tags = split(tags) }
            note.isPinned = options.flag("--pin")
            note.content = body(options.positional(), stdin: stdin) ?? ""
            try options.finish()
            try storage.save(note)
            return try encode(full(note))
        case "edit":
            var note = try find(try options.positional("id"), in: storage)
            if let title = options.value("--title") { note.title = title }
            if let content = options.value("--content") { note.content = body(content, stdin: stdin) ?? "" }
            if let tags = options.value("--tags") { note.tags = split(tags) }
            if let c = try color(options.value("--color")) { note.colorName = c }
            if options.flag("--pin") { note.isPinned = true }
            if options.flag("--unpin") { note.isPinned = false }
            try options.finish()
            note.modifiedAt = Date()
            try storage.save(note)
            return try encode(full(note))
        case "archive", "unarchive":
            var note = try find(try options.positional("id"), in: storage)
            try options.finish()
            note.isArchived = verb == "archive"
            note.modifiedAt = Date()
            try storage.save(note)
            return try encode(full(note))
        case "delete":
            let note = try find(try options.positional("id"), in: storage)
            try options.finish()
            try storage.delete(id: note.id)
            return try encode(["deleted": note.id.uuidString])
        default:
            throw Failure(message: "unknown command '\(verb)'\n\n" + usage)
        }
    }

    // MARK: - Arguments

    /// Consumes flags and values as they are asked for; whatever is left over is an error.
    struct Options {
        private var args: [String]
        init(_ args: [String]) { self.args = args }

        mutating func flag(_ name: String) -> Bool {
            guard let i = args.firstIndex(of: name) else { return false }
            args.remove(at: i)
            return true
        }

        mutating func value(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            let v = args[i + 1]
            args.removeSubrange(i...i + 1)
            return v
        }

        mutating func positional(_ name: String) throws -> String {
            guard let v = positional() else { throw Failure(message: "missing <\(name)>") }
            return v
        }

        mutating func positional() -> String? {
            guard let i = args.firstIndex(where: { !$0.hasPrefix("--") || $0 == "-" }) else { return nil }
            return args.remove(at: i)
        }

        func finish() throws {
            guard args.isEmpty else { throw Failure(message: "unexpected argument '\(args[0])'") }
        }
    }

    private static func body(_ text: String?, stdin: String) -> String? {
        text == "-" ? stdin : text
    }

    private static func split(_ tags: String) -> [String] {
        tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func color(_ name: String?) throws -> String? {
        guard let name else { return nil }
        guard PastelColor(rawValue: name) != nil else {
            throw Failure(message: "unknown colour '\(name)'; one of \(PastelColor.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return name
    }

    static func find(_ prefix: String, in storage: Storage) throws -> Note {
        let matches = try storage.loadAll().filter { $0.id.uuidString.lowercased().hasPrefix(prefix.lowercased()) }
        switch matches.count {
        case 1: return matches[0]
        case 0: throw Failure(message: "no note with id '\(prefix)'")
        default: throw Failure(message: "'\(prefix)' matches \(matches.count) notes; give more of the id")
        }
    }

    // MARK: - Output

    static func summary(_ note: Note) -> [String: Any] {
        var out: [String: Any] = [
            "id": note.id.uuidString,
            "title": note.title,
            "color": note.colorName,
            "tags": note.tags,
            "pinned": note.isPinned,
            "archived": note.isArchived,
            "modifiedAt": iso.string(from: note.modifiedAt),
            "excerpt": note.excerpt(lines: 2),
        ]
        if let url = note.preview?.url { out["link"] = url.absoluteString }
        return out
    }

    static func full(_ note: Note) -> [String: Any] {
        var out = summary(note)
        out.removeValue(forKey: "excerpt")
        out["content"] = note.content
        out["createdAt"] = iso.string(from: note.createdAt)
        out["attachments"] = note.attachments
        if let p = note.preview {
            out["preview"] = ["url": p.url.absoluteString, "title": p.title as Any, "description": p.description as Any,
                              "site": p.siteName as Any, "detail": p.detail as Any]
        }
        return out
    }

    private static let iso = ISO8601DateFormatter()

    private static func encode(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
