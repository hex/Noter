// ABOUTME: Asks a model for a title, a four-line summary, tags, and a color, through a local agent CLI
// ABOUTME: (agy, claude, codex) in print mode with a JSON schema, or the Anthropic API with a stored key.

import Foundation

struct Enrichment: Codable, Equatable {
    var title: String
    var summary: String
    var tags: [String]
    var color: String
}

enum EnricherError: Error, Equatable {
    case binaryNotFound(String)
    case cli(String)
    case badReply(String)
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
                var args = ["-p", prompt, "--model", model, "--effort", "low", "--output-format", "json", "--json-schema", Enricher.schemaJSON]
                if readsFiles { args.append("--dangerously-skip-permissions") }
                return args
            case .claude:
                var args = ["-p", prompt, "--model", model, "--output-format", "json", "--json-schema", Enricher.schemaJSON]
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
        let prompt = prompt(for: note, attachments: attachments)
        let output: Data
        if let provider = backend.tool.provider {
            guard let key = APIKey.load(provider) else { throw EnricherError.cli("No \(backend.tool.label) stored") }
            output = try await callAPI(request(prompt: prompt, model: backend.model, tool: backend.tool, apiKey: key))
        } else {
            output = try await run(backend, prompt: prompt, readsFiles: !attachments.isEmpty)
        }
        return apply(try parse(output), to: note)
    }

    static func prompt(for note: Note, attachments: [URL] = []) -> String {
        var prompt = """
        You file items someone shared from their phone into a sticky-notes app. Given a page title and \
        whatever text was captured, write a short specific title (at most 8 words), a summary of exactly \
        four lines separated by newlines (each under 70 characters, plain sentences), one to four lowercase \
        topic tags, and pick a sticky-note color from: \(PastelColor.allCases.map(\.rawValue).joined(separator: ", ")). \
        The note already shows the source link and site name, so never repeat the URL, the site, or the \
        title in the summary, and never comment on how much context was captured. Work only from what is \
        given; if it is thin, describe what the item is in fewer words. Reply with JSON only.

        Page title: \(note.title)

        Captured:
        \(note.content)
        """
        if let preview = note.preview {
            prompt += "\n\nLink preview (\(preview.siteName ?? "site")):"
            if let t = preview.title { prompt += "\nTitle: \(t)" }
            if let d = preview.description { prompt += "\nText: \(d)" }
        }
        if !attachments.isEmpty {
            prompt += "\n\nAttached files, read each one and describe what it shows:\n"
            prompt += attachments.map { "- \($0.path)" }.joined(separator: "\n")
        }
        return prompt
    }

    /// Reads the enrichment out of the reply. agy and claude wrap it in a JSON envelope
    /// (`structured_output`, else the text field `response` / `result`); codex prints the object
    /// among decoration lines; the API returns it as the text of the first content block.
    static func parse(_ data: Data) throws -> Enrichment {
        let decoder = JSONDecoder()
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            guard let json = firstJSONObject(in: String(decoding: data, as: UTF8.self)) else {
                throw EnricherError.badReply("no JSON in reply")
            }
            return try decoder.decode(Enrichment.self, from: Data(json.utf8))
        }
        if let error = envelope["error"] as? [String: Any], let message = error["message"] as? String {
            throw EnricherError.cli(message)
        }
        if let text = apiText(in: envelope), let json = firstJSONObject(in: text) {
            return try decoder.decode(Enrichment.self, from: Data(json.utf8))
        }
        if let error = envelope["error"] as? String, !error.isEmpty { throw EnricherError.cli(error) }
        if envelope["is_error"] as? Bool == true { throw EnricherError.cli(envelope["result"] as? String ?? "claude error") }

        if let structured = envelope["structured_output"] {
            if let object = structured as? [String: Any] {
                return try decoder.decode(Enrichment.self, from: JSONSerialization.data(withJSONObject: object))
            }
            if let text = structured as? String, let json = firstJSONObject(in: text) {
                return try decoder.decode(Enrichment.self, from: Data(json.utf8))
            }
        }
        guard let text = (envelope["response"] ?? envelope["result"]) as? String,
              let json = firstJSONObject(in: text) else {
            throw EnricherError.badReply("no JSON in reply")
        }
        return try decoder.decode(Enrichment.self, from: Data(json.utf8))
    }

    /// The reply text of an Anthropic, OpenAI, or Gemini response.
    private static func apiText(in envelope: [String: Any]) -> String? {
        if let content = envelope["content"] as? [[String: Any]] { return content.first?["text"] as? String }
        if let choices = envelope["choices"] as? [[String: Any]] {
            return (choices.first?["message"] as? [String: Any])?["content"] as? String
        }
        if let candidates = envelope["candidates"] as? [[String: Any]],
           let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] {
            return parts.first?["text"] as? String
        }
        return nil
    }

    /// The first balanced `{...}` in free text, so trailing objects or code fences are ignored.
    static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for i in text.indices[start...] {
            let c = text[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(text[start...i]) }
            default: break
            }
        }
        return nil
    }

    /// The summary becomes the body. A bare URL first line is kept only when there is no preview to hold it.
    static func apply(_ e: Enrichment, to note: Note) -> Note {
        var out = note
        out.title = e.title
        let url = note.content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        out.content = url.hasPrefix("http") && note.preview == nil ? "\(url)\n\n\(e.summary)" : e.summary
        out.tags = e.tags
        if PastelColor(rawValue: e.color) != nil { out.colorName = e.color }
        out.modifiedAt = Date()
        return out
    }

    static let schemaJSON = """
    {"type":"object","properties":{"title":{"type":"string"},"summary":{"type":"string"},\
    "tags":{"type":"array","items":{"type":"string"}},"color":{"type":"string"}},\
    "required":["title","summary","tags","color"],"additionalProperties":false}
    """

    /// codex takes its schema as a file path; written once per launch.
    static func schemaFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "noter-enrichment-schema.json")
        if !FileManager.default.fileExists(atPath: url.path) { try? schemaJSON.write(to: url, atomically: true, encoding: .utf8) }
        return url
    }

    // MARK: - API

    static func request(prompt: String, model: String, tool: Tool, apiKey: String) throws -> URLRequest {
        let schema = try JSONSerialization.jsonObject(with: Data(schemaJSON.utf8)) as! [String: Any]
        let url: String
        var headers = ["content-type": "application/json"]
        let body: [String: Any]
        switch tool {
        case .openAIAPI:
            url = "https://api.openai.com/v1/chat/completions"
            headers["Authorization"] = "Bearer \(apiKey)"
            body = [
                "model": model,
                "messages": [["role": "user", "content": prompt]],
                "response_format": ["type": "json_schema", "json_schema": ["name": "enrichment", "strict": true, "schema": schema]],
            ]
        case .geminiAPI:
            url = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
            headers["x-goog-api-key"] = apiKey
            // Gemini rejects JSON Schema keywords it does not know.
            var geminiSchema = schema
            geminiSchema.removeValue(forKey: "additionalProperties")
            body = [
                "contents": [["parts": [["text": prompt]]]],
                "generationConfig": ["responseMimeType": "application/json", "responseSchema": geminiSchema],
            ]
        case .anthropicAPI, .agy, .claude, .codex:
            url = "https://api.anthropic.com/v1/messages"
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"
            body = [
                "model": model,
                "max_tokens": 1024,
                "messages": [["role": "user", "content": prompt]],
                "output_config": ["format": ["type": "json_schema", "schema": schema]],
            ]
        }
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func callAPI(_ request: URLRequest) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
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
