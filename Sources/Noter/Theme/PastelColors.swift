// ABOUTME: Sticky note color palette for note tabs and panels.
// ABOUTME: Saturated Post-it style colors with dark text for readability.

import AppKit
import NoterKit

extension PastelColor {
    /// Saturated background — the full note body color, like a real sticky note.
    var background: NSColor {
        switch self {
        case .lavender: NSColor.sRGB(0xc5, 0xb8, 0xf0)
        case .mint:     NSColor.sRGB(0x8e, 0xe8, 0xc0)
        case .peach:    NSColor.sRGB(0xfe, 0xc8, 0xa0)
        case .sky:      NSColor.sRGB(0x8e, 0xd0, 0xf0)
        case .rose:     NSColor.sRGB(0xf8, 0xb0, 0xc0)
        case .lemon:    NSColor.sRGB(0xfc, 0xf0, 0x80)
        case .coral:    NSColor.sRGB(0xfe, 0xa8, 0x98)
        case .sage:     NSColor.sRGB(0xb0, 0xd8, 0x98)
        }
    }

    /// Dark foreground text color for contrast on the saturated background.
    var foreground: NSColor {
        switch self {
        case .lavender: NSColor.sRGB(0x2e, 0x1f, 0x5e)
        case .mint:     NSColor.sRGB(0x1a, 0x4a, 0x35)
        case .peach:    NSColor.sRGB(0x6a, 0x30, 0x10)
        case .sky:      NSColor.sRGB(0x1a, 0x40, 0x68)
        case .rose:     NSColor.sRGB(0x6a, 0x1a, 0x30)
        case .lemon:    NSColor.sRGB(0x5a, 0x4e, 0x0a)
        case .coral:    NSColor.sRGB(0x6a, 0x20, 0x18)
        case .sage:     NSColor.sRGB(0x28, 0x48, 0x1e)
        }
    }

}

extension NSColor {
    /// Creates an NSColor from 0-255 integer RGB components in sRGB color space.
    static func sRGB(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        let rf: CGFloat = CGFloat(r) / 255.0
        let gf: CGFloat = CGFloat(g) / 255.0
        let bf: CGFloat = CGFloat(b) / 255.0
        return NSColor(red: rf, green: gf, blue: bf, alpha: 1.0)
    }
}
