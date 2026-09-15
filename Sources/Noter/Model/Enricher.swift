// ABOUTME: Asks a model for a title, a four-line summary, tags, and a color, through a local agent CLI
// ABOUTME: (agy, claude, codex) in print mode with a JSON schema, or a provider API through NoterKit.

import Foundation
import NoterKit

enum EnricherError: Error, Equatable {
    case binaryNotFound(String)
    case cli(String)
    case timedOut
}

enum Enricher {
    /// What runs the prompt. The CLI tools share print-mode flags; the API is a plain HTTPS call.
    enum Tool: String, CaseIterable, Identifiable {
        case agy, claude, codex, anthropicAPI, openAIAPI, geminiAPI
        var id: String { rawValue }

        var label: String {
            switch self {
            case .agy: "agy"
            case .claude: "Claude Code"
            case .codex: "Codex"
            case .anthropicAPI: "Anthropic API key"
            case .openAIAPI: "OpenAI API key"
            case .geminiAPI: "Gemini API key"
            }
        }

        var binary: String? {
            switch self {
            case .agy: "agy"
            case .claude: "claude"
            case .codex: "codex"
            case .anthropicAPI, .openAIAPI, .geminiAPI: nil
            }
        }

        var provider: APIProvider? {
            switch self {
            case .anthropicAPI: .anthropic
            case .openAIAPI: .openai
            case .geminiAPI: .gemini
            case .agy, .claude, .codex: nil
            }
        }

        var defaultModel: String { models[0] }

        /// Suggestions; any model name can be typed instead.
        var models: [String] {
            switch self {
            case .agy: ["gemini-3.8-flash", "gemini-3.8-pro"]
            case .claude: ["claude-haiku-4-5", "claude-sonnet-5", "claude-opus-5"]
            case .codex: ["gpt-6-astra", "gpt-5.4", "gpt-5.4-mini"]
            case .anthropicAPI: ["claude-haiku-4-5", "claude-sonnet-5", "claude-opus-5"]
            case .openAIAPI: ["gpt-5.4-mini", "gpt-5.4"]
            case .geminiAPI: ["gemini-3.8-flash", "gemini-3.8-pro"]
            }
        }

        /// A CLI counts as available when its binary is on disk; the API when a key is stored.
        var isAvailable: Bool {
            guard let binary else { return provider.flatMap(APIKey.load) != nil }
            return (try? Enricher.locate(binary)) != nil
        }
    }

    struct Backend: Equatable {
        let tool: Tool
        let model: String

        static let agyGeminiFlash = Backend(tool: .agy, model: "gemini-3.8-flash")
        static let claudeHaiku = Backend(tool: .claude, model: "claude-haiku-4-5")

        func arguments(prompt: String, readsFiles: Bool = false) -> [String] {
            switch tool {
            case .agy:
                var args = ["-p", prompt, "--model", model, "--effort", "low", "--output-format", "json", "--json-schema", EnrichmentAPI.schemaJSON]
                if readsFiles { args.append("--dangerously-skip-permissions") }
                return args
            case .claude:
                var args = ["-p", prompt, "--model", model, "--output-format", "json", "--json-schema", EnrichmentAPI.schemaJSON]
                if readsFiles { args += ["--allowedTools", "Read"] }
                args.append("--no-session-persistence")
                return args
            case .codex:
                return ["exec", "--skip-git-repo-check", "--sandbox", "read-only", "-m", model,
                        "--output-schema", Enricher.schemaFile().path, prompt]
            case .anthropicAPI, .openAIAPI, .geminiAPI:
                return []
            }
        }
    }

    static var backend = Backend.agyGeminiFlash

    static func enrich(_ note: Note, attachments: [URL] = []) async throws -> Note {
        if let provider = backend.tool.provider {
            return try await EnrichmentAPI.enrich(note, provider: provider, model: backend.model)
        }
        let prompt = EnrichmentAPI.prompt(for: note, attachments: attachments)
        let output = try await run(backend, prompt: prompt, readsFiles: !attachments.isEmpty)
        return EnrichmentAPI.apply(try EnrichmentAPI.parse(output), to: note)
    }

    /// codex takes its schema as a file path; written once per launch.
    static func schemaFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "noter-enrichment-schema.json")
        if !FileManager.default.fileExists(atPath: url.path) { try? EnrichmentAPI.schemaJSON.write(to: url, atomically: true, encoding: .utf8) }
        return url
    }

    // MARK: - Process

    /// Longer than any sane enrichment; a hung tool is killed rather than left as a zombie.
    static let cliTimeout: TimeInterval = 180

    private static func run(_ backend: Backend, prompt: String, readsFiles: Bool) async throws -> Data {
        guard let binary = backend.tool.binary else { throw EnricherError.binaryNotFound(backend.tool.rawValue) }
        let path = try locate(binary)
        // A stale key in the environment would override the CLI's own login.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        env.removeValue(forKey: "CLAUDECODE")
        return try await ProcessRunner.run(
            executable: path, arguments: backend.arguments(prompt: prompt, readsFiles: readsFiles),
            environment: env, timeout: cliTimeout
        )
    }

    /// GUI apps have no shell PATH, so look where the CLIs are usually installed, including nvm's node
    /// bins. Found paths are remembered; a path that stops being executable is looked up again.
    private static var located: [String: String] = [:]

    static func locate(_ binary: String) throws -> String {
        if let known = located[binary], FileManager.default.isExecutableFile(atPath: known) { return known }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let common = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"].map { "\($0)/\(binary)" }
        var found = common.first { FileManager.default.isExecutableFile(atPath: $0) }
        if found == nil {
            let nodeBins = ((try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node")) ?? [])
                .sorted().reversed().map { "\(home)/.nvm/versions/node/\($0)/bin/\(binary)" }
            found = nodeBins.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        guard let found else { throw EnricherError.binaryNotFound(binary) }
        located[binary] = found
        return found
    }
}
