// ABOUTME: Tests for per-site link unfurls: routing by host and path, and parsing each site's API reply.
// ABOUTME: Fixtures are trimmed literal replies with placeholder authors; no network.

import Testing
import Foundation
@testable import NoterKit

@Suite("Unfurls")
struct UnfurlTests {
    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test("GitHub repo and issue links route to the API, other GitHub pages to the page")
    func githubRouting() {
        #expect(LinkPreview.site(for: url("https://github.com/sparkle-project/Sparkle")) == .github(owner: "sparkle-project", repo: "Sparkle", issue: nil))
        #expect(LinkPreview.site(for: url("https://github.com/o/r/issues/91870#issuecomment-1")) == .github(owner: "o", repo: "r", issue: 91870))
        #expect(LinkPreview.site(for: url("https://github.com/o/r/pull/12")) == .github(owner: "o", repo: "r", issue: 12))
        #expect(LinkPreview.site(for: url("https://github.com/hex")) == nil)
        #expect(LinkPreview.site(for: url("https://github.com/o/r/blob/main/README.md")) == nil)
    }

    @Test("GitHub repo reply: name as title, stars and language as detail, avatar as image")
    func githubRepo() throws {
        let json = #"{"full_name":"sparkle-project/Sparkle","description":"A software update framework for macOS","stargazers_count":9707,"language":"Objective-C","open_issues_count":17,"owner":{"login":"sparkle-project","avatar_url":"https://avatars.example/u/1"}}"#
        let p = try LinkPreview.parseGitHubRepo(Data(json.utf8), url: url("https://github.com/sparkle-project/Sparkle"))
        #expect(p.siteName == "GitHub")
        #expect(p.title == "sparkle-project/Sparkle")
        #expect(p.description == "A software update framework for macOS")
        #expect(p.detail == "★ 9.7k · Objective-C")
        #expect(p.imageURL?.absoluteString == "https://avatars.example/u/1")
    }

    @Test("GitHub issue reply: title, state and comments, first body line as description")
    func githubIssue() throws {
        let json = ##"{"title":"Make plugins 10x more powerful","state":"open","number":91870,"comments":165,"user":{"login":"jane-roe","avatar_url":"https://avatars.example/u/2"},"body":"# Community Update\n\n> **AI;DR**: We're shipping in N weeks.\n\nThank you all."}"##
        let p = try LinkPreview.parseGitHubIssue(Data(json.utf8), url: url("https://github.com/o/r/issues/91870"))
        #expect(p.title == "Make plugins 10x more powerful")
        #expect(p.description == "Community Update AI;DR: We're shipping in N weeks. Thank you all.")
        #expect(p.detail == "o/r #91870 · open · 165 comments")
        #expect(p.imageURL?.absoluteString == "https://avatars.example/u/2")
    }

    @Test("Counts are shortened the way GitHub shows them")
    func compactCounts() {
        #expect(LinkPreview.compact(0) == "0")
        #expect(LinkPreview.compact(999) == "999")
        #expect(LinkPreview.compact(1000) == "1k")
        #expect(LinkPreview.compact(9707) == "9.7k")
        #expect(LinkPreview.compact(12400) == "12k")
        #expect(LinkPreview.compact(1_200_000) == "1.2M")
    }

    @Test("Reddit posts, YouTube videos and HN items route to their APIs; other pages do not")
    func otherRouting() {
        #expect(LinkPreview.site(for: url("https://reddit.com/r/swift/comments/1abc/some_title/")) == .reddit)
        #expect(LinkPreview.site(for: url("https://www.reddit.com/r/swift/s/abc")) == nil)
        #expect(LinkPreview.site(for: url("https://www.youtube.com/watch?v=dQw4w9WgXcQ")) == .youtube)
        #expect(LinkPreview.site(for: url("https://youtu.be/dQw4w9WgXcQ")) == .youtube)
        #expect(LinkPreview.site(for: url("https://www.youtube.com/@channel")) == nil)
        #expect(LinkPreview.site(for: url("https://news.ycombinator.com/item?id=8863")) == .hackerNews(id: 8863))
        #expect(LinkPreview.site(for: url("https://news.ycombinator.com/newest")) == nil)
    }

    @Test("Reddit oEmbed: post title, subreddit and author from the embed markup")
    func reddit() throws {
        let json = #"{"author_name":"jane_roe","html":"<blockquote class=\"reddit-embed-bq\" style=\"height:316px\" >\n<a href=\"https://www.reddit.com/r/smarthome/comments/1/x/\">What device made you wonder &amp; wait?</a><br> by\n<a href=\"https://www.reddit.com/user/jane_roe/\">u/jane_roe</a> in\n<a href=\"https://www.reddit.com/r/smarthome/\">smarthome</a>\n</blockquote>","provider_name":"reddit","type":"rich"}"#
        let p = try LinkPreview.parseRedditOEmbed(Data(json.utf8), url: url("https://www.reddit.com/r/smarthome/comments/1/x/"))
        #expect(p.siteName == "r/smarthome")
        #expect(p.title == "What device made you wonder & wait?")
        #expect(p.description == nil)
        #expect(p.detail == "u/jane_roe")
        #expect(p.imageURL == nil)
    }

    @Test("YouTube oEmbed: video title, channel as detail, thumbnail as image")
    func youtube() throws {
        let json = #"{"title":"Never Gonna Give You Up","author_name":"Some Channel","type":"video","provider_name":"YouTube","thumbnail_url":"https://i.ytimg.com/vi/x/hqdefault.jpg"}"#
        let p = try LinkPreview.parseYouTubeOEmbed(Data(json.utf8), url: url("https://youtu.be/x"))
        #expect(p.siteName == "YouTube")
        #expect(p.title == "Never Gonna Give You Up")
        #expect(p.detail == "Some Channel")
        #expect(p.imageURL?.absoluteString == "https://i.ytimg.com/vi/x/hqdefault.jpg")
    }

    @Test("Hacker News item: title, points and comments, linked site as description")
    func hackerNews() throws {
        let json = #"{"by":"john_doe","descendants":71,"id":8863,"score":104,"title":"My YC app: Dropbox - Throw away your USB drive","type":"story","url":"http://www.getdropbox.com/u/2/screencast.html"}"#
        let p = try LinkPreview.parseHackerNews(Data(json.utf8), url: url("https://news.ycombinator.com/item?id=8863"))
        #expect(p.siteName == "Hacker News")
        #expect(p.title == "My YC app: Dropbox - Throw away your USB drive")
        #expect(p.description == "www.getdropbox.com")
        #expect(p.detail == "104 points · 71 comments")
        #expect(p.imageURL == nil)
    }
}
