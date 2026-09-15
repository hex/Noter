// ABOUTME: Turns a captured note into a title, a four-line summary, tags and a colour: the prompt, the
// ABOUTME: JSON schema, the direct API calls (Anthropic, OpenAI, Gemini) and the reading of every reply shape.

import Foundation

public struct Enrichment: Codable, Equatable {
    public var title: String
    public var summary: String
    public var tags: [String]
    public var color: String

    public init(title: String, summary: String, tags: [String], color: String) {
        self.title = title
        self.summary = summary
        self.tags = tags
        self.color = color
    }
}

public enum EnrichmentError: Error, Equatable {
    /// The reply held no enrichment.
    case badReply(String)
    /// The API or tool answered with an error message of its own.
    case remote(String)
    case missingKey(APIProvider)
}

public enum EnrichmentAPI {
    /// Asks `provider` directly with the stored key; the Mac's agent CLIs go through `Enricher` instead.
    public static func enrich(_ note: Note, provider: APIProvider, model: String) async throws -> Note {
        guard let key = APIKey.load(provider) else { throw EnrichmentError.missingKey(provider) }
        let data = try await callAPI(try request(prompt: prompt(for: note), model: model, provider: provider, apiKey: key))
        return apply(try parse(data), to: note)
    }

    public static func prompt(for note: Note, attachments: [URL] = []) -> String {
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
    public static func parse(_ data: Data) throws -> Enrichment {
        let decoder = JSONDecoder()
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            guard let json = firstJSONObject(in: String(decoding: data, as: UTF8.self)) else {
                throw EnrichmentError.badReply("no JSON in reply")
            }
            return try decoder.decode(Enrichment.self, from: Data(json.utf8))
        }
        if let error = envelope["error"] as? [String: Any], let message = error["message"] as? String {
            throw EnrichmentError.remote(message)
        }
        if let text = apiText(in: envelope), let json = firstJSONObject(in: text) {
            return try decoder.decode(Enrichment.self, from: Data(json.utf8))
        }
        if let error = envelope["error"] as? String, !error.isEmpty { throw EnrichmentError.remote(error) }
        if envelope["is_error"] as? Bool == true { throw EnrichmentError.remote(envelope["result"] as? String ?? "claude error") }

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
            throw EnrichmentError.badReply("no JSON in reply")
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
    public static func firstJSONObject(in text: String) -> String? {
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
    public static func apply(_ e: Enrichment, to note: Note) -> Note {
        var out = note
        out.title = e.title
        let url = note.content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        out.content = url.hasPrefix("http") && note.preview == nil ? "\(url)\n\n\(e.summary)" : e.summary
        out.tags = e.tags
        if PastelColor(rawValue: e.color) != nil { out.colorName = e.color }
        out.modifiedAt = Date()
        return out
    }

    public static let schemaJSON = """
    {"type":"object","properties":{"title":{"type":"string"},"summary":{"type":"string"},\
    "tags":{"type":"array","items":{"type":"string"}},"color":{"type":"string"}},\
    "required":["title","summary","tags","color"],"additionalProperties":false}
    """

    public static func request(prompt: String, model: String, provider: APIProvider, apiKey: String) throws -> URLRequest {
        let schema = try JSONSerialization.jsonObject(with: Data(schemaJSON.utf8)) as! [String: Any]
        let url: String
        var headers = ["content-type": "application/json"]
        let body: [String: Any]
        switch provider {
        case .openai:
            url = "https://api.openai.com/v1/chat/completions"
            headers["Authorization"] = "Bearer \(apiKey)"
            body = [
                "model": model,
                "messages": [["role": "user", "content": prompt]],
                "response_format": ["type": "json_schema", "json_schema": ["name": "enrichment", "strict": true, "schema": schema]],
            ]
        case .gemini:
            url = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
            headers["x-goog-api-key"] = apiKey
            // Gemini rejects JSON Schema keywords it does not know.
            var geminiSchema = schema
            geminiSchema.removeValue(forKey: "additionalProperties")
            body = [
                "contents": [["parts": [["text": prompt]]]],
                "generationConfig": ["responseMimeType": "application/json", "responseSchema": geminiSchema],
            ]
        case .anthropic:
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
}
