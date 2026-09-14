// ABOUTME: A link's title, description, site, and image, fetched from OpenGraph tags or X's oEmbed.
// ABOUTME: Stored on the note so the card can show a preview and the enricher has text to summarize.

import Foundation

struct LinkPreview: Codable, Equatable, Sendable {
    var url: URL
    var title: String?
    var description: String?
    var siteName: String?
    var imageURL: URL?
    /// Name of the downloaded image in the attachments folder, once fetched.
    var imageName: String?
    /// Name of the downloaded site icon in the attachments folder, once fetched.
    var faviconName: String?

    var faviconURL: URL? {
        guard let host = url.host() else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }

    // MARK: - Fetching

    static func fetch(_ url: URL) async throws -> LinkPreview {
        if usesOEmbed(url) {
            var components = URLComponents(string: "https://publish.x.com/oembed")!
            components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "omit_script", value: "true")]
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            return try parseOEmbed(data, url: url)
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh) AppleWebKit/605.1.15 (KHTML, like Gecko) Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        return parseHTML(String(decoding: data.prefix(512 * 1024), as: UTF8.self), url: url)
    }

    static func usesOEmbed(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"].contains(host)
    }

    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url).first { $0.scheme?.hasPrefix("http") == true }
    }

    // MARK: - Parsing

    static func parseHTML(_ html: String, url: URL) -> LinkPreview {
        func meta(_ property: String) -> String? {
            let pattern = #"<meta\s+(?:[^>]*?\s)?(?:property|name)=["']"# + NSRegularExpression.escapedPattern(for: property)
                + #"["'][^>]*?\scontent=["']([^"']*)["']|<meta\s+(?:[^>]*?\s)?content=["']([^"']*)["'][^>]*?\s(?:property|name)=["']"#
                + NSRegularExpression.escapedPattern(for: property) + #"["']"#
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else { return nil }
            for i in 1...2 {
                if let r = Range(m.range(at: i), in: html) { return decodeEntities(String(html[r])) }
            }
            return nil
        }
        var titleTag: String?
        if let re = try? NSRegularExpression(pattern: #"<title[^>]*>([^<]*)</title>"#, options: [.caseInsensitive]),
           let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let r = Range(m.range(at: 1), in: html) {
            titleTag = decodeEntities(String(html[r])).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return LinkPreview(
            url: url,
            title: meta("og:title") ?? titleTag,
            description: meta("og:description") ?? meta("description"),
            siteName: meta("og:site_name") ?? url.host(),
            imageURL: meta("og:image").flatMap { URL(string: $0, relativeTo: url)?.absoluteURL },
            imageName: nil
        )
    }

    static func parseOEmbed(_ data: Data, url: URL) throws -> LinkPreview {
        struct Reply: Decodable { var author_name: String?; var html: String?; var provider_name: String? }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        var text: String?
        if let html = reply.html,
           let body = html.range(of: #"<p[^>]*>(.*?)</p>"#, options: [.regularExpression, .caseInsensitive]) {
            var inner = String(html[body])
            inner = inner.replacingOccurrences(of: #"^<p[^>]*>|</p>$"#, with: "", options: .regularExpression)
            inner = inner.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            inner = inner.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            text = decodeEntities(inner).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return LinkPreview(url: url, title: reply.author_name, description: text, siteName: reply.provider_name ?? "X", imageURL: nil, imageName: nil)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "—", "&nbsp;": " "] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }
}
