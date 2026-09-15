// ABOUTME: A link's title, description, site, and image, fetched from OpenGraph tags or a site's own API.
// ABOUTME: Stored on the note so the card can show a preview and the enricher has text to summarize.

import Foundation

public struct LinkPreview: Codable, Equatable, Sendable {
    public var url: URL
    public var title: String?
    public var description: String?
    public var siteName: String?
    public var imageURL: URL?
    /// A site-specific line such as stars and language, or points and comments. Sidecars written
    /// before this existed decode as nil.
    public var detail: String?
    /// Name of the downloaded image in the attachments folder, once fetched.
    public var imageName: String?
    /// Name of the downloaded site icon in the attachments folder, once fetched.
    public var faviconName: String?
    /// When the image and icon were last attempted, so a site that never serves one is not retried
    /// on every launch. Sidecars written before this existed decode as nil.
    public var assetsFetchedAt: Date?

    public init(url: URL, title: String? = nil, description: String? = nil, siteName: String? = nil, imageURL: URL? = nil,
                detail: String? = nil, imageName: String? = nil, faviconName: String? = nil, assetsFetchedAt: Date? = nil) {
        self.url = url
        self.title = title
        self.description = description
        self.siteName = siteName
        self.imageURL = imageURL
        self.detail = detail
        self.imageName = imageName
        self.faviconName = faviconName
        self.assetsFetchedAt = assetsFetchedAt
    }

    /// Dates as the sidecar stores them, to the second.
    public var withWholeSecondDates: LinkPreview {
        var copy = self
        copy.assetsFetchedAt = assetsFetchedAt.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) }
        return copy
    }

    public var faviconURL: URL? {
        guard let host = url.host() else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }

    // MARK: - Fetching

    /// Sites whose own API gives a better card than their OpenGraph tags.
    public enum Site: Equatable {
        case x
        case github(owner: String, repo: String, issue: Int?)
        case reddit
        case youtube
        case hackerNews(id: Int)
    }

    public static func site(for url: URL) -> Site? {
        let host = url.host()?.lowercased() ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com":
            return .x
        case "github.com", "www.github.com":
            guard parts.count >= 2 else { return nil }
            if parts.count == 2 { return .github(owner: parts[0], repo: parts[1], issue: nil) }
            if parts.count == 4, ["issues", "pull"].contains(parts[2]), let number = Int(parts[3]) {
                return .github(owner: parts[0], repo: parts[1], issue: number)
            }
            return nil
        case "reddit.com", "www.reddit.com", "old.reddit.com":
            return parts.count >= 4 && parts[0] == "r" && parts[2] == "comments" ? .reddit : nil
        case "youtu.be":
            return parts.count == 1 ? .youtube : nil
        case "youtube.com", "www.youtube.com", "m.youtube.com":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let isWatch = parts.first == "watch" && query.contains { $0.name == "v" }
            return isWatch || parts.first == "shorts" ? .youtube : nil
        case "news.ycombinator.com":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard parts.first == "item", let id = query.first(where: { $0.name == "id" })?.value.flatMap(Int.init) else { return nil }
            return .hackerNews(id: id)
        default:
            return nil
        }
    }

    public static func fetch(_ url: URL) async throws -> LinkPreview {
        // A site API can rate-limit or change shape; the page's own tags are the fallback either way.
        if let site = site(for: url), let preview = try? await fetchFromAPI(site, url: url) {
            return preview
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh) AppleWebKit/605.1.15 (KHTML, like Gecko) Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        // Meta tags live in the head; half a megabyte is plenty and the rest is never fetched.
        let page = try await LimitedDownload.fetch(request, limit: 512 * 1024)
        return parseHTML(String(decoding: page.data, as: UTF8.self), url: url)
    }

    private static func fetchFromAPI(_ site: Site, url: URL) async throws -> LinkPreview {
        switch site {
        case .x:
            let data = try await json("https://publish.x.com/oembed", query: ["url": url.absoluteString, "omit_script": "true"])
            return try parseOEmbed(data, url: url)
        case let .github(owner, repo, issue):
            let base = "https://api.github.com/repos/\(owner)/\(repo)"
            if let issue {
                return try parseGitHubIssue(try await json("\(base)/issues/\(issue)"), url: url)
            }
            return try parseGitHubRepo(try await json(base), url: url)
        case .reddit:
            return try parseRedditOEmbed(try await json("https://www.reddit.com/oembed", query: ["url": url.absoluteString]), url: url)
        case .youtube:
            return try parseYouTubeOEmbed(try await json("https://www.youtube.com/oembed", query: ["url": url.absoluteString, "format": "json"]), url: url)
        case let .hackerNews(id):
            return try parseHackerNews(try await json("https://hacker-news.firebaseio.com/v0/item/\(id).json"), url: url)
        }
    }

    private static func json(_ endpoint: String, query: [String: String] = [:]) async throws -> Data {
        var components = URLComponents(string: endpoint)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.setValue("Noter", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return try await LimitedDownload.fetch(request, limit: 256 * 1024).data
    }

    public static func usesOEmbed(_ url: URL) -> Bool { site(for: url) == .x }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    public static func firstURL(in text: String) -> URL? {
        guard let detector = linkDetector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var found: URL?
        detector.enumerateMatches(in: text, range: range) { match, _, stop in
            if let url = match?.url, url.scheme?.hasPrefix("http") == true { found = url; stop.pointee = true }
        }
        return found
    }

    // MARK: - Parsing

    /// The meta tags a preview reads, compiled once; the set is fixed so a dictionary is enough.
    private static let metaPatterns: [String: NSRegularExpression] = Dictionary(uniqueKeysWithValues:
        ["og:title", "og:description", "description", "og:site_name", "og:image"].map { property in
            let pattern = #"<meta\s+(?:[^>]*?\s)?(?:property|name)=["']"# + NSRegularExpression.escapedPattern(for: property)
                + #"["'][^>]*?\scontent=["']([^"']*)["']|<meta\s+(?:[^>]*?\s)?content=["']([^"']*)["'][^>]*?\s(?:property|name)=["']"#
                + NSRegularExpression.escapedPattern(for: property) + #"["']"#
            return (property, try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))
        })
    private static let titlePattern = try! NSRegularExpression(pattern: #"<title[^>]*>([^<]*)</title>"#, options: [.caseInsensitive])

    public static func parseHTML(_ html: String, url: URL) -> LinkPreview {
        func meta(_ property: String) -> String? {
            guard let re = metaPatterns[property],
                  let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else { return nil }
            for i in 1...2 {
                if let r = Range(m.range(at: i), in: html) { return decodeEntities(String(html[r])) }
            }
            return nil
        }
        var titleTag: String?
        if let m = titlePattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let r = Range(m.range(at: 1), in: html) {
            titleTag = decodeEntities(String(html[r])).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let siteName = meta("og:site_name") ?? url.host()
        return LinkPreview(
            url: url,
            title: (meta("og:title") ?? titleTag).map { withoutSitePrefix($0, site: siteName) },
            description: meta("og:description") ?? meta("description"),
            siteName: siteName,
            imageURL: meta("og:image").flatMap { URL(string: $0, relativeTo: url)?.absoluteURL },
            imageName: nil
        )
    }

    /// "GitHub - owner/repo" reads as "owner/repo" next to a GitHub label; a title that merely starts
    /// with the site's name, like "GitHub Actions", is left alone.
    public static func withoutSitePrefix(_ title: String, site: String?) -> String {
        guard let site, !site.isEmpty else { return title }
        for separator in [" - ", " – ", " — ", " | ", ": "] {
            let prefix = site + separator
            if title.lowercased().hasPrefix(prefix.lowercased()), title.count > prefix.count {
                return String(title.dropFirst(prefix.count))
            }
        }
        return title
    }

    public static func parseOEmbed(_ data: Data, url: URL) throws -> LinkPreview {
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

    public static func parseGitHubRepo(_ data: Data, url: URL) throws -> LinkPreview {
        struct Owner: Decodable { var avatar_url: String? }
        struct Reply: Decodable { var full_name: String; var description: String?; var stargazers_count: Int; var language: String?; var owner: Owner? }
        let r = try JSONDecoder().decode(Reply.self, from: data)
        return LinkPreview(url: url, title: r.full_name, description: r.description, siteName: "GitHub",
                           imageURL: r.owner?.avatar_url.flatMap(URL.init),
                           detail: ["★ " + compact(r.stargazers_count), r.language].compactMap { $0 }.joined(separator: " · "))
    }

    public static func parseGitHubIssue(_ data: Data, url: URL) throws -> LinkPreview {
        struct User: Decodable { var avatar_url: String? }
        struct Reply: Decodable { var title: String; var state: String; var number: Int; var comments: Int; var user: User?; var body: String? }
        let r = try JSONDecoder().decode(Reply.self, from: data)
        let parts = url.pathComponents.filter { $0 != "/" }
        let repo = parts.prefix(2).joined(separator: "/")
        return LinkPreview(url: url, title: r.title, description: r.body.map(plainMarkdown), siteName: "GitHub",
                           imageURL: r.user?.avatar_url.flatMap(URL.init),
                           detail: "\(repo) #\(r.number) · \(r.state) · \(r.comments) comments")
    }

    /// Reddit's oEmbed carries no fields beyond the author; title and subreddit sit in the embed's anchors.
    public static func parseRedditOEmbed(_ data: Data, url: URL) throws -> LinkPreview {
        struct Reply: Decodable { var author_name: String?; var html: String? }
        let r = try JSONDecoder().decode(Reply.self, from: data)
        let anchors = anchorTexts(in: r.html ?? "")
        let subreddit = url.pathComponents.filter { $0 != "/" }.dropFirst().first
        return LinkPreview(url: url, title: anchors.first, description: nil,
                           siteName: subreddit.map { "r/" + $0 } ?? "Reddit", imageURL: nil,
                           detail: r.author_name.map { "u/" + $0 })
    }

    public static func parseYouTubeOEmbed(_ data: Data, url: URL) throws -> LinkPreview {
        struct Reply: Decodable { var title: String?; var author_name: String?; var thumbnail_url: String? }
        let r = try JSONDecoder().decode(Reply.self, from: data)
        return LinkPreview(url: url, title: r.title, description: nil, siteName: "YouTube",
                           imageURL: r.thumbnail_url.flatMap(URL.init), detail: r.author_name)
    }

    public static func parseHackerNews(_ data: Data, url: URL) throws -> LinkPreview {
        struct Reply: Decodable { var title: String?; var score: Int?; var descendants: Int?; var url: String? }
        let r = try JSONDecoder().decode(Reply.self, from: data)
        return LinkPreview(url: url, title: r.title, description: r.url.flatMap(URL.init)?.host(), siteName: "Hacker News",
                           imageURL: nil, detail: "\(r.score ?? 0) points · \(r.descendants ?? 0) comments")
    }

    private static let anchorPattern = try! NSRegularExpression(pattern: #"<a\s[^>]*>([^<]*)</a>"#, options: [.caseInsensitive])

    public static func anchorTexts(in html: String) -> [String] {
        anchorPattern.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
            Range(m.range(at: 1), in: html).map { decodeEntities(String(html[$0])).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    /// Markdown body flattened to one line of prose: headings, quotes and emphasis marks dropped.
    public static func plainMarkdown(_ body: String) -> String {
        body.split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: #"^[#>\s]+"#, with: "", options: .regularExpression)
                     .replacingOccurrences(of: #"[*_`]+"#, with: "", options: .regularExpression)
                     .trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 9707 → "9.7k", 12400 → "12k", 1200000 → "1.2M".
    public static func compact(_ n: Int) -> String {
        func short(_ value: Double, _ suffix: String) -> String {
            value < 10 ? String(format: "%.1f", value).replacingOccurrences(of: ".0", with: "") + suffix : "\(Int(value))" + suffix
        }
        if n >= 1_000_000 { return short(Double(n) / 1_000_000, "M") }
        if n >= 1_000 { return short(Double(n) / 1_000, "k") }
        return "\(n)"
    }

    public static func decodeEntities(_ s: String) -> String {
        var out = s
        for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "—", "&nbsp;": " "] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }
}
