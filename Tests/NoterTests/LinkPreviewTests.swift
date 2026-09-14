// ABOUTME: Tests for link preview parsing: OpenGraph tags from HTML and X's oEmbed reply.
// ABOUTME: Fixtures are literal snippets; no network.

import Testing
import Foundation
@testable import Noter

@Suite("Link Preview")
struct LinkPreviewTests {
    @Test("OpenGraph tags become a preview, entities decoded")
    func openGraph() {
        let html = """
        <html><head><title>Fallback</title>
        <meta property="og:title" content="Material &amp; Light">
        <meta content="A background material type." property="og:description">
        <meta property="og:image" content="https://developer.apple.com/tutorials/developer-og.jpg">
        <meta property="og:site_name" content="Apple Developer">
        </head></html>
        """
        let p = LinkPreview.parseHTML(html, url: URL(string: "https://developer.apple.com/documentation/swiftui/material")!)
        #expect(p.title == "Material & Light")
        #expect(p.description == "A background material type.")
        #expect(p.imageURL?.absoluteString == "https://developer.apple.com/tutorials/developer-og.jpg")
        #expect(p.siteName == "Apple Developer")
    }

    @Test("Without OpenGraph the title tag and host are used")
    func fallbacks() {
        let p = LinkPreview.parseHTML("<title>Plain Page</title>", url: URL(string: "https://blog.example.com/post")!)
        #expect(p.title == "Plain Page")
        #expect(p.description == nil)
        #expect(p.siteName == "blog.example.com")
    }

    @Test("X oEmbed gives the author as title and the stripped tweet as description")
    func oembed() throws {
        let json = #"{"author_name":"Peter Steinberger 🦞","html":"<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">Fixed so many little perf issues that didn&#39;t matter much.<br><br>OC stems ~80 sessions here. <a href=\"https://t.co/x\">pic.twitter.com/x</a></p>&mdash; Peter Steinberger (@steipete) <a href=\"https://x.com/steipete/status/1\">September 13, 2026</a></blockquote>","provider_name":"X"}"#
        let p = try LinkPreview.parseOEmbed(Data(json.utf8), url: URL(string: "https://x.com/steipete/status/1")!)
        #expect(p.title == "Peter Steinberger 🦞")
        #expect(p.description == "Fixed so many little perf issues that didn't matter much.\n\nOC stems ~80 sessions here. pic.twitter.com/x")
        #expect(p.siteName == "X")
    }

    @Test("X and Twitter links route to oEmbed, others to the page")
    func routing() {
        #expect(LinkPreview.usesOEmbed(URL(string: "https://x.com/a/status/1")!))
        #expect(LinkPreview.usesOEmbed(URL(string: "https://twitter.com/a/status/1")!))
        #expect(!LinkPreview.usesOEmbed(URL(string: "https://example.com/x")!))
    }

    @Test("The first http link in a note body is the one previewed")
    func firstLink() {
        #expect(LinkPreview.firstURL(in: "see\nhttps://a.example/x and https://b.example")?.host() == "a.example")
        #expect(LinkPreview.firstURL(in: "no links") == nil)
    }
}
