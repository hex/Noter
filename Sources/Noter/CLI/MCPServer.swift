// ABOUTME: Serves the noter verbs as MCP tools over stdio: newline-delimited JSON-RPC 2.0, one request per line.
// ABOUTME: Each tool call runs the same CLI code path and returns its JSON as the tool's text content.

import Foundation
import NoterKit

struct MCPServer {
    let storage: Storage
    static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    /// Reads requests from stdin until it closes, answering each on stdout.
    func serve() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty,
                  let request = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            guard let reply = handle(request),
                  let data = try? JSONSerialization.data(withJSONObject: reply) else { continue }
            FileHandle.standardOutput.write(data + Data("\n".utf8))
        }
    }

    /// One request in, one response out; nil for notifications, which get no answer.
    func handle(_ request: [String: Any]) -> [String: Any]? {
        let method = request["method"] as? String ?? ""
        let params = request["params"] as? [String: Any] ?? [:]
        guard let id = request["id"] else { return nil }
        func reply(_ result: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }
        func error(_ code: Int, _ message: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        }
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            let version = Self.supportedVersions.contains(asked) ? asked : "2025-06-18"
            return reply([
                "protocolVersion": version,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "noter", "version": AppInfo(info: AppInfo.executableBundle.infoDictionary ?? [:]).version],
                "instructions": "Noter is a menu-bar sticky-note app. Notes have a title, markdown content, tags, a pastel colour, and pin/archive flags. Ids are UUIDs and may be abbreviated to a unique prefix.",
            ])
        case "ping":
            return reply([:])
        case "tools/list":
            return reply(["tools": Self.tools])
        case "tools/call":
            guard let name = params["name"] as? String, Self.tools.contains(where: { $0["name"] as? String == name }) else {
                return error(-32602, "unknown tool")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let result = CLI.run(arguments: Self.cliArguments(for: name, arguments), storage: storage, stdin: arguments["content"] as? String ?? "")
            let failed = result.exitCode != 0

            return reply([
                "content": [["type": "text", "text": failed ? result.stderr : result.stdout]],
                "isError": failed,
            ])
        default:
            return error(-32601, "method not found: \(method)")
        }
    }

    // MARK: - Tools

    private static func schema(_ properties: [String: [String: Any]], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }
    private static let idProperty: [String: Any] = ["type": "string", "description": "Note id, or a unique prefix of it"]
    private static let noteProperties: [String: [String: Any]] = [
        "title": ["type": "string"],
        "content": ["type": "string", "description": "Markdown body"],
        "tags": ["type": "array", "items": ["type": "string"]],
        "color": ["type": "string", "enum": PastelColor.allCases.map(\.rawValue)],
        "pinned": ["type": "boolean"],
    ]

    static let tools: [[String: Any]] = [
        ["name": "list_notes", "description": "List notes, newest first, with an excerpt of each. Active notes by default.",
         "inputSchema": schema(["archived": ["type": "boolean", "description": "Only archived notes"],
                                "all": ["type": "boolean", "description": "Active and archived"]])],
        ["name": "get_note", "description": "One note with its full markdown content.",
         "inputSchema": schema(["id": idProperty], required: ["id"])],
        ["name": "add_note", "description": "Create a note.", "inputSchema": schema(noteProperties)],
        ["name": "edit_note", "description": "Change only the fields given on an existing note.",
         "inputSchema": schema(noteProperties.merging(["id": idProperty]) { a, _ in a }, required: ["id"])],
        ["name": "archive_note", "description": "Hide a note from the rail.", "inputSchema": schema(["id": idProperty], required: ["id"])],
        ["name": "unarchive_note", "description": "Bring an archived note back.", "inputSchema": schema(["id": idProperty], required: ["id"])],
        ["name": "delete_note", "description": "Delete a note permanently.", "inputSchema": schema(["id": idProperty], required: ["id"])],
    ]

    /// The CLI already validates and formats; tools are a thin translation onto its arguments.
    static func cliArguments(for tool: String, _ a: [String: Any]) -> [String] {
        var args: [String] = []
        func common() {
            if let t = a["title"] as? String { args += ["--title", t] }
            if let tags = a["tags"] as? [String] { args += ["--tags", tags.joined(separator: ",")] }
            if let c = a["color"] as? String { args += ["--color", c] }
        }
        switch tool {
        case "list_notes":
            args = ["list"]
            if a["all"] as? Bool == true { args.append("--all") } else if a["archived"] as? Bool == true { args.append("--archived") }
        case "get_note": args = ["show", a["id"] as? String ?? ""]
        case "add_note":
            args = ["add"]; common()
            if a["pinned"] as? Bool == true { args.append("--pin") }
            if a["content"] != nil { args.append("-") }
        case "edit_note":
            args = ["edit", a["id"] as? String ?? ""]; common()
            if let p = a["pinned"] as? Bool { args.append(p ? "--pin" : "--unpin") }
            if a["content"] != nil { args += ["--content", "-"] }
        case "archive_note": args = ["archive", a["id"] as? String ?? ""]
        case "unarchive_note": args = ["unarchive", a["id"] as? String ?? ""]
        case "delete_note": args = ["delete", a["id"] as? String ?? ""]
        default: break
        }
        return args
    }
}
