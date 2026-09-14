// ABOUTME: Tests for the CLI-backed enricher: the command it builds and how it reads each CLI's JSON envelope.
// ABOUTME: No processes are spawned; fixtures stand in for agy and claude output.

import Testing
import Foundation
@testable import Noter

@Suite("Enricher")
struct EnricherTests {
    private let note = Note(
        title: "Someone on X", colorName: "sky",
        content: "https://x.com/someone/status/1\n\nA long post about SwiftUI materials.",
        tags: ["inbox"]
    )

    @Test("agy is invoked in print mode with model, effort, JSON output and the schema")
    func agyArguments() {
        let args = Enricher.Backend(tool: .agy, model: "gemini-3.8-flash").arguments(prompt: "P")
        #expect(args.starts(with: ["-p", "P", "--model", "gemini-3.8-flash", "--effort", "low", "--output-format", "json"]))
        #expect(args.contains("--json-schema"))
    }

    @Test("claude is invoked with Haiku and no session persistence")
    func claudeArguments() {
        let args = Enricher.Backend(tool: .claude, model: "claude-haiku-4-5").arguments(prompt: "P")
        #expect(args.starts(with: ["-p", "P", "--model", "claude-haiku-4-5", "--output-format", "json"]))
        #expect(args.contains("--no-session-persistence"))
    }

    @Test("Attachments add their paths to the prompt and unlock file reading")
    func attachments() {
        let url = URL(fileURLWithPath: "/tmp/att/receipt.jpg")
        #expect(Enricher.prompt(for: note, attachments: [url]).contains("/tmp/att/receipt.jpg"))
        #expect(Enricher.Backend.claudeHaiku.arguments(prompt: "P", readsFiles: true).contains("--allowedTools"))
        #expect(!Enricher.Backend.claudeHaiku.arguments(prompt: "P").contains("--allowedTools"))
        #expect(Enricher.Backend.agyGeminiFlash.arguments(prompt: "P", readsFiles: true).contains("--dangerously-skip-permissions"))
    }

    @Test("codex runs exec non-interactively with the model, a schema file, and the prompt last")
    func codexArguments() {
        let args = Enricher.Backend(tool: .codex, model: "gpt-6-astra").arguments(prompt: "P")
        #expect(args.starts(with: ["exec", "--skip-git-repo-check", "--sandbox", "read-only", "-m", "gpt-6-astra", "--output-schema"]))
        #expect(args.last == "P")
        #expect(FileManager.default.fileExists(atPath: args[7]))
    }

    @Test("codex's plain stdout, JSON among decoration lines, is parsed")
    func parseCodex() throws {
        let out = "\u{1B}[35mcodex\u{1B}[0m\n{\"title\":\"T\",\"summary\":\"a\\nb\",\"tags\":[],\"color\":\"mint\"}\n\u{1B}[2mtokens used\u{1B}[0m\n24,558\n"
        #expect(try Enricher.parse(Data(out.utf8)).title == "T")
    }

    @Test("Anthropic request: key header, model, schema-constrained output")
    func anthropicRequest() throws {
        let r = try Enricher.request(prompt: "P", model: "claude-haiku-4-5", tool: .anthropicAPI, apiKey: "k")
        #expect(r.url?.host() == "api.anthropic.com")
        #expect(r.value(forHTTPHeaderField: "x-api-key") == "k")
        let body = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
        #expect(body["model"] as? String == "claude-haiku-4-5")
        #expect((body["output_config"] as? [String: Any]) != nil)
    }

    @Test("OpenAI request: bearer token, chat completions, json_schema response format")
    func openAIRequest() throws {
        let r = try Enricher.request(prompt: "P", model: "gpt-5.4-mini", tool: .openAIAPI, apiKey: "k")
        #expect(r.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        let body = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
        let format = body["response_format"] as? [String: Any]
        #expect(format?["type"] as? String == "json_schema")
    }

    @Test("Gemini request: key header, model in the path, JSON response schema without additionalProperties")
    func geminiRequest() throws {
        let r = try Enricher.request(prompt: "P", model: "gemini-3.8-flash", tool: .geminiAPI, apiKey: "k")
        #expect(r.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        #expect(r.value(forHTTPHeaderField: "x-goog-api-key") == "k")
        let body = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
        let config = body["generationConfig"] as? [String: Any]
        #expect(config?["responseMimeType"] as? String == "application/json")
        let schema = config?["responseSchema"] as? [String: Any]
        #expect(schema?["additionalProperties"] == nil)
    }

    @Test("Replies from the three APIs are parsed from their text field")
    func parseAPIs() throws {
        let inner = #"{\"title\":\"T\",\"summary\":\"s\",\"tags\":[],\"color\":\"mint\"}"#
        let anthropic = #"{"content":[{"type":"text","text":"\#(inner)"}]}"#
        let openai = #"{"choices":[{"message":{"role":"assistant","content":"\#(inner)"}}]}"#
        let gemini = #"{"candidates":[{"content":{"parts":[{"text":"\#(inner)"}]}}]}"#
        for reply in [anthropic, openai, gemini] {
            #expect(try Enricher.parse(Data(reply.utf8)).title == "T")
        }
    }

    @Test("API error envelopes surface their message")
    func parseAPIError() {
        let reply = #"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        #expect(throws: EnricherError.cli("invalid x-api-key")) { try Enricher.parse(Data(reply.utf8)) }
    }

    @Test("Every tool has a default model and the CLI tools name a binary")
    func toolDefaults() {
        for tool in Enricher.Tool.allCases { #expect(!tool.defaultModel.isEmpty) }
        #expect(Enricher.Tool.codex.binary == "codex")
        #expect(Enricher.Tool.anthropicAPI.binary == nil)
    }

    @Test("A link preview's text reaches the prompt")
    func previewInPrompt() {
        var n = note
        n.preview = LinkPreview(url: URL(string: "https://x.com/a/status/1")!, title: "Author", description: "the tweet body", siteName: "X", imageURL: nil, imageName: nil)
        #expect(Enricher.prompt(for: n).contains("the tweet body"))
    }

    @Test("The prompt carries the captured content")
    func prompt() {
        #expect(Enricher.prompt(for: note).contains("https://x.com/someone/status/1"))
    }

    @Test("agy's envelope is parsed from its response field")
    func parseAgy() throws {
        let out = #"{"conversation_id":"1","status":"SUCCESS","response":"{\"title\":\"T\",\"summary\":\"a\\nb\\nc\\nd\",\"tags\":[\"x\"],\"color\":\"mint\"}\n"}"#
        let e = try Enricher.parse(Data(out.utf8))
        #expect(e.title == "T")
        #expect(e.summary.split(separator: "\n").count == 4)
        #expect(e.tags == ["x"])
        #expect(e.color == "mint")
    }

    @Test("A structured_output object wins over the prose, and extra keys are ignored")
    func parseStructured() throws {
        let out = #"{"status":"SUCCESS","response":"```json\n{\"title\":\"wrong\"}\n```","structured_output":{"title":"Right","summary":"s","tags":["t"],"color":"sky","toolAction":"done"}}"#
        #expect(try Enricher.parse(Data(out.utf8)).title == "Right")
    }

    @Test("Prose with a fenced object followed by a second object takes the first balanced object")
    func parseTwoObjects() throws {
        let out = #"{"status":"SUCCESS","response":"```json\n{\"title\":\"A\",\"summary\":\"s\",\"tags\":[],\"color\":\"mint\"}\n```\n{\"color\":\"sky\",\"title\":\"B\"}"}"#
        #expect(try Enricher.parse(Data(out.utf8)).title == "A")
    }

    @Test("claude's envelope is parsed from its result field")
    func parseClaude() throws {
        let out = #"{"type":"result","subtype":"success","is_error":false,"result":"{\"title\":\"T\",\"summary\":\"s\",\"tags\":[],\"color\":\"rose\"}"}"#
        #expect(try Enricher.parse(Data(out.utf8)).color == "rose")
    }

    @Test("A CLI error envelope is reported")
    func parseError() {
        let out = #"{"status":"ERROR","response":"","error":"invalid model selection"}"#
        #expect(throws: EnricherError.self) { try Enricher.parse(Data(out.utf8)) }
    }

    @Test("Without a preview the source URL stays above the summary; the inbox tag is replaced")
    func apply() {
        let e = Enrichment(title: "T", summary: "S1\nS2\nS3\nS4", tags: ["a", "b"], color: "mint")
        let out = Enricher.apply(e, to: note)
        #expect(out.title == "T")
        #expect(out.content == "https://x.com/someone/status/1\n\nS1\nS2\nS3\nS4")
        #expect(out.tags == ["a", "b"])
        #expect(out.colorName == "mint")
    }

    @Test("With a preview the body is only the summary; the link lives in the byline")
    func applyWithPreview() {
        var n = note
        n.preview = LinkPreview(url: URL(string: "https://x.com/someone/status/1")!, title: "A", description: nil, siteName: "X", imageURL: nil, imageName: nil)
        let out = Enricher.apply(Enrichment(title: "T", summary: "S", tags: [], color: "mint"), to: n)
        #expect(out.content == "S")
    }

    @Test("An unknown color from the model falls back to the note's own color")
    func badColor() {
        let e = Enrichment(title: "T", summary: "S", tags: [], color: "chartreuse")
        #expect(Enricher.apply(e, to: note).colorName == "sky")
    }
}
