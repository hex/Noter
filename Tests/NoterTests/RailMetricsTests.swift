// ABOUTME: Tests for RailMetrics, the shared window-size math for the frosted rail and glass card.
// ABOUTME: Worked examples: 3 notes collapsed and with one note open.

import Testing
@testable import Noter

@Suite("Rail Metrics")
struct RailMetricsTests {
    // Strip: 8pt padding, 3 dots of 16 with two 8pt gaps, 12pt gap, 14pt plus, 8pt padding = 106.
    // Window adds a 40pt shadow margin top and bottom.
    @Test("Collapsed height for three notes")
    func collapsedThree() {
        #expect(RailMetrics.collapsedHeight(noteCount: 3) == 186)
    }

    // The window reserves the card's 520 maximum; the strip (82) is shorter. Plus the margins.
    @Test("Expanded height for three notes")
    func expandedThree() {
        #expect(RailMetrics.expandedHeight(noteCount: 3) == 600)
    }

    // The rail shows 7 dots and scrolls the rest: 16 + 7*16 + 6*8 + 12 + 14 = 202, plus margins.
    @Test("The strip stops growing at seven dots")
    func capped() {
        #expect(RailMetrics.collapsedHeight(noteCount: 25) == 282)
        #expect(RailMetrics.collapsedHeight(noteCount: 7) == 282)
        #expect(RailMetrics.expandedHeight(noteCount: 25) == 600)
    }

    // 40 margin + 10 inset + 36 strip = 86; expanded adds 10 gap + 320 card.
    @Test("Window widths")
    func widths() {
        #expect(RailMetrics.collapsedWidth == 86)
        #expect(RailMetrics.expandedWidth == 416)
    }
}

@Suite("Rail Metrics with a chosen dot cap")
struct RailMetricsDotCapTests {
    // Cap 3: 16 + 3*16 + 2*8 + 12 + 14 = 106, plus 80 margins.
    @Test("The strip stops growing at the chosen cap")
    func customCap() {
        #expect(RailMetrics.collapsedHeight(noteCount: 25, visibleDots: 3) == 186)
        #expect(RailMetrics.dotsHeight(noteCount: 25, visibleDots: 3) == 64)
        // Cap 10, above the shipping default: 10*16 + 9*8.
        #expect(RailMetrics.dotsHeight(noteCount: 25, visibleDots: 10) == 232)
    }
}
