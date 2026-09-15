// ABOUTME: Tests for the MCP server behind `noter mcp`: handshake, tool listing, and tool calls as JSON-RPC.
// ABOUTME: Each request is a dictionary in, a dictionary (or nothing, for notifications) out; no stdio.

import Testing
import Foundation
@testable import Noter
@testable import NoterKit

@Suite("MCP")
struct MCPTests {
    let server: MCPServer

    init() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("noter-mcp-test-\(UUID().uuidString)")
        server = MCPServer(storage: Storage(rootDirectory: dir))
    }

    private func call(_ method: String, _ params: [String: Any] = [:], id: Int? = 1) -> [String: Any]? {
        var req: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        if let id { req["id"] = id }
        return server.handle(req)
    }

    @Test("initialize answers with the client's protocol version, a tools capability and server info")
    func initialize() throws {
        let reply = try #require(call("initialize", ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "t", "version": "0"]]))
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "noter")
        #expect(reply["id"] as? Int == 1)
        #expect(call("notifications/initialized", id: nil) == nil)
    }

    @Test("tools/list names every verb with an input schema")
    func toolsList() throws {
        let tools = try #require((call("tools/list")?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        #expect(names == ["list_notes", "get_note", "add_note", "edit_note", "archive_note", "unarchive_note", "delete_note"])
        #expect(tools.allSatisfy { ($0["inputSchema"] as? [String: Any])?["type"] as? String == "object" })
    }

    @Test("tools/call add_note then get_note round-trips through disk")
    func addAndGet() throws {
        let added = try #require(call("tools/call", ["name": "add_note", "arguments": ["title": "Via MCP", "content": "hello", "tags": ["a", "b"]]]))
        let result = try #require(added["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let text = try #require(((result["content"] as? [[String: Any]])?.first?["text"]) as? String)
        let note = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(note["title"] as? String == "Via MCP")
        let id = try #require(note["id"] as? String)
        let got = try #require(call("tools/call", ["name": "get_note", "arguments": ["id": String(id.prefix(6))]])?["result"] as? [String: Any])
        let gotText = try #require(((got["content"] as? [[String: Any]])?.first?["text"]) as? String)
        #expect(gotText.contains("\"content\" : \"hello\""))
    }

    @Test("a failing tool reports isError; an unknown method is a JSON-RPC error")
    func errors() throws {
        let missing = try #require(call("tools/call", ["name": "get_note", "arguments": ["id": "zzz"]])?["result"] as? [String: Any])
        #expect(missing["isError"] as? Bool == true)
        let unknown = try #require(call("nope"))
        #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
    }
}
