// ABOUTME: Tests for ImageCache, the in-memory store of decoded attachment images.
// ABOUTME: Checks that a file is decoded once, misses stay cheap, and removal forces a re-read.

import AppKit
import Testing
@testable import Noter

@Suite("Image cache")
struct ImageCacheTests {
    private func writePNG(_ color: NSColor, to url: URL) throws {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            color.setFill(); rect.fill(); return true
        }
        let tiff = image.tiffRepresentation!
        let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
        try png.write(to: url)
    }

    @Test("The same file decodes once and later reads come from memory")
    func decodesOnce() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ImageCacheTests-\(UUID().uuidString).png")
        try writePNG(.red, to: url)
        let cache = ImageCache()
        let first = try #require(cache.image(at: url))
        try FileManager.default.removeItem(at: url)
        let second = try #require(cache.image(at: url))
        #expect(first === second)
    }

    @Test("A missing file is nil and is not remembered as a hit")
    func missing() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ImageCacheTests-\(UUID().uuidString).png")
        let cache = ImageCache()
        #expect(cache.image(at: url) == nil)
        try writePNG(.blue, to: url)
        #expect(cache.image(at: url) != nil)
    }

    @Test("Forgetting a file makes the next read hit the disk again")
    func forget() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "ImageCacheTests-\(UUID().uuidString).png")
        try writePNG(.red, to: url)
        let cache = ImageCache()
        let first = try #require(cache.image(at: url))
        cache.forget(url)
        let second = try #require(cache.image(at: url))
        #expect(first !== second)
    }
}
