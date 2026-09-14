// ABOUTME: Decoded attachment images (favicons, previews, thumbnails) kept in memory, keyed by file URL.
// ABOUTME: Views ask here instead of NSImage(contentsOf:), which would re-read the file on every render.

import AppKit

final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, NSImage>()

    init(costLimit: Int = 40 * 1024 * 1024) {
        cache.totalCostLimit = costLimit
    }

    /// The decoded image, or nil when the file is missing or not an image. Misses are not cached,
    /// so a file that appears later (a preview still downloading) is picked up on the next ask.
    func image(at url: URL) -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let image = NSImage(contentsOf: url) else { return nil }
        let pixels = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
        cache.setObject(image, forKey: url as NSURL, cost: pixels * 4)
        return image
    }

    /// Drop one entry, for when the file at that URL is replaced or deleted.
    func forget(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}
