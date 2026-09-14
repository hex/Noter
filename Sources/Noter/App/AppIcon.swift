// ABOUTME: The app's mark, drawn in code: a rounded card with a rail of three dots on its right edge.
// ABOUTME: Rendered as a template image so the menu bar tints it for light and dark, and larger for About.

import AppKit

enum AppIcon {
    /// Menu bar size. Template images take the bar's own colour.
    static func statusItem() -> NSImage {
        let image = draw(size: 18, lineWidth: 1.3)
        image.isTemplate = true
        return image
    }

    /// The app icon from the asset catalog, for About. Falls back to the drawn mark when running outside the bundle.
    static func artwork() -> NSImage {
        NSImage(named: "AppIcon") ?? draw(size: 64, lineWidth: 1.2)
    }

    static func draw(size: CGFloat, lineWidth: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = size / 18
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let card = NSRect(x: 2.5 * s, y: 2 * s, width: 10 * s, height: 14 * s)
            let path = NSBezierPath(roundedRect: card, xRadius: 2.5 * s, yRadius: 2.5 * s)
            path.lineWidth = lineWidth * s
            path.stroke()
            for i in 0..<3 {
                let y = card.minY + (1.7 + CGFloat(i) * 4.3) * s
                NSBezierPath(ovalIn: NSRect(x: card.maxX + 1.2 * s, y: y, width: 3 * s, height: 3 * s)).fill()
            }
            return true
        }
        return image
    }
}
