// ABOUTME: Shared geometry for the frosted rail and glass card so SwiftUI layout and the NSPanel frame agree.
// ABOUTME: The window includes a shadow margin so drop shadows are not clipped at its bounds.

import Foundation

enum RailMetrics {
    static let edgeInset: CGFloat = 10
    static let stripWidth: CGFloat = 36
    static let stripPadding: CGFloat = 8
    static let dot: CGFloat = 16
    static let dotGap: CGFloat = 8
    /// Dots shown before the rail starts to scroll, unless Settings says otherwise.
    static let visibleDots = 7
    static let plusButton: CGFloat = 14
    static let plusGap: CGFloat = 12
    static let cardGap: CGFloat = 10
    static let cardWidth: CGFloat = 320
    static let cardMinHeight: CGFloat = 240
    static let cardMaxHeight: CGFloat = 520
    /// Window space reserved for the card; the card itself sizes to its content within the min and max.
    static let cardHeight: CGFloat = cardMaxHeight
    static let cardRadius: CGFloat = 14
    static let shadowMargin: CGFloat = 40

    static var collapsedWidth: CGFloat { shadowMargin + edgeInset + stripWidth }
    static var expandedWidth: CGFloat { collapsedWidth + cardGap + cardWidth }

    static func stripHeight(noteCount: Int, visibleDots: Int = visibleDots) -> CGFloat {
        let n = CGFloat(min(noteCount, visibleDots))
        return stripPadding * 2 + n * dot + max(n - 1, 0) * dotGap + plusGap + plusButton
    }

    static func dotsHeight(noteCount: Int, visibleDots: Int = visibleDots) -> CGFloat {
        let n = CGFloat(min(noteCount, visibleDots))
        return n * dot + max(n - 1, 0) * dotGap
    }

    static func collapsedHeight(noteCount: Int, visibleDots: Int = visibleDots) -> CGFloat {
        stripHeight(noteCount: noteCount, visibleDots: visibleDots) + shadowMargin * 2
    }

    static func expandedHeight(noteCount: Int, visibleDots: Int = visibleDots) -> CGFloat {
        max(stripHeight(noteCount: noteCount, visibleDots: visibleDots), cardHeight) + shadowMargin * 2
    }
}
