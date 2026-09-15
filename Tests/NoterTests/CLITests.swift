// ABOUTME: Tests for the noter command line: each verb against a temporary library, JSON output parsed back.
// ABOUTME: Runs the same code path the noter binary does, with stdin and the library directory injected.

import Testing
import Foundation
@testable import Noter
@testable import NoterKit

@Suite("CLI")
struct CLITests {
    let storage: Storage

    init() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("noter-cli-test-\(UUID().uuidString)")
        storage = Storage(rootDirectory: dir)
    }

    private func run(_ args: String..., stdin: String = "") -> CLI.Result {
        CLI.run(arguments: args, storage: storage, stdin: stdin)
    }

    private func json(_ s: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(s.utf8))
    }

    @Test("list on an empty library prints an empty array")
    func emptyList() throws {
        let r = run("list")
        #expect(r.exitCode == 0)
        #expect((try json(r.stdout) as? [Any])?.isEmpty == true)
    }

    @Test("add creates a note with title, tags, colour and body, and prints it")
    func add() throws {
        let r = run("add", "--title", "Groceries", "--tags", "home,food", "--color", "mint", "milk\neggs")
        #expect(r.exitCode == 0)
        let note = try #require(try json(r.stdout) as? [String: Any])
        #expect(note["title"] as? String == "Groceries")
        #expect(note["tags"] as? [String] == ["home", "food"])
        #expect(note["color"] as? String == "mint")
        #expect(note["content"] as? String == "milk\neggs")
        let id = try #require(UUID(uuidString: note["id"] as! String))
        #expect(try storage.load(id: id).content == "milk\neggs")
    }

    @Test("add reads the body from stdin when told to, and rejects an unknown colour")
    func addFromStdin() throws {
        let r = run("add", "--title", "Piped", "-", stdin: "from stdin\n")
        #expect(r.exitCode == 0)
        #expect((try json(r.stdout) as? [String: Any])?["content"] as? String == "from stdin\n")
        let bad = run("add", "--color", "mauve", "x")
        #expect(bad.exitCode == 1)
        #expect(bad.stderr.contains("mauve"))
    }

    @Test("show accepts an id prefix; list hides archived notes unless asked")
    func showAndList() throws {
        let a = try storage.saved(Note(title: "Alpha", colorName: "sky", content: "one"))
        var b = Note(title: "Beta", colorName: "sky"); b.isArchived = true
        try storage.save(b)
        let shown = run("show", String(a.id.uuidString.prefix(8)))
        #expect(shown.exitCode == 0)
        #expect((try json(shown.stdout) as? [String: Any])?["title"] as? String == "Alpha")
        let titles = { (r: CLI.Result) in (try? self.json(r.stdout) as? [[String: Any]])?.compactMap { $0["title"] as? String } ?? [] }
        #expect(titles(run("list")) == ["Alpha"])
        #expect(titles(run("list", "--archived")) == ["Beta"])
        #expect(Set(titles(run("list", "--all"))) == ["Alpha", "Beta"])
        #expect(run("show", "nope").exitCode == 1)
    }

    @Test("edit replaces the fields given, bumps modifiedAt, and keeps the rest")
    func edit() throws {
        let note = try storage.saved(Note(title: "Old", colorName: "sky", content: "body", tags: ["t"], modifiedAt: Date(timeIntervalSinceNow: -60)))
        let r = run("edit", note.id.uuidString, "--title", "New", "--content", "-", "--pin", stdin: "new body")
        #expect(r.exitCode == 0)
        let after = try storage.load(id: note.id)
        #expect(after.title == "New")
        #expect(after.content == "new body")
        #expect(after.tags == ["t"])
        #expect(after.isPinned)
        #expect(after.modifiedAt > note.modifiedAt)
    }

    @Test("archive, unarchive and delete change exactly that")
    func lifecycle() throws {
        let note = try storage.saved(Note(title: "A", colorName: "sky"))
        #expect(run("archive", note.id.uuidString).exitCode == 0)
        #expect(try storage.load(id: note.id).isArchived)
        #expect(run("unarchive", note.id.uuidString).exitCode == 0)
        #expect(try storage.load(id: note.id).isArchived == false)
        #expect(run("delete", note.id.uuidString).exitCode == 0)
        #expect(try storage.loadAll().isEmpty)
    }

    @Test("no verb or --help prints usage; an unknown verb fails")
    func help() {
        #expect(run().stdout.contains("noter list"))
        #expect(run("--help").exitCode == 0)
        #expect(run("frobnicate").exitCode == 1)
    }
}

private extension Storage {
    func saved(_ note: Note) throws -> Note { try save(note); return note }
}
