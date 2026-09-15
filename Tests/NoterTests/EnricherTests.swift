// ABOUTME: Tests for the Mac enricher: the command line built for each agent CLI and the tool catalogue.
// ABOUTME: No processes are spawned; prompt, parsing and API tests live in NoterKit.

import Testing
import Foundation
@testable import Noter
@testable import NoterKit

@Suite("Enricher")
struct EnricherTests {
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
        #expect(EnrichmentAPI.prompt(for: Note(title: "T", colorName: "sky"), attachments: [url]).contains("/tmp/att/receipt.jpg"))
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

    @Test("Every tool has a default model and the CLI tools name a binary")
    func toolDefaults() {
        for tool in Enricher.Tool.allCases { #expect(!tool.defaultModel.isEmpty) }
        #expect(Enricher.Tool.codex.binary == "codex")
        #expect(Enricher.Tool.anthropicAPI.binary == nil)
    }
}
