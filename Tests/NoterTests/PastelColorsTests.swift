// ABOUTME: Tests for the pastel color palette — lookup, cycling, and completeness.
// ABOUTME: Validates all 8 color pairs exist with correct hex values.

import Testing
import AppKit
@testable import Noter

@Suite("Pastel Colors")
struct PastelColorsTests {
    @Test("All 8 colors are defined")
    func allColorsDefined() {
        #expect(PastelColor.allCases.count == 8)
    }

    @Test("Lookup by name returns correct color")
    func lookupByName() {
        let lavender = PastelColor(rawValue: "lavender")
        #expect(lavender != nil)
        #expect(lavender == .lavender)
    }

    @Test("Background and foreground are distinct for each color")
    func backgroundForegroundDistinct() {
        for color in PastelColor.allCases {
            #expect(color.background != color.foreground)
        }
    }

    @Test("Next color cycles through all colors and wraps around")
    func nextColorCycles() {
        var current = PastelColor.allCases.first!
        var visited = Set<PastelColor>()

        for _ in 0..<PastelColor.allCases.count {
            visited.insert(current)
            current = current.next
        }

        #expect(visited.count == PastelColor.allCases.count)
        #expect(current == PastelColor.allCases.first!)
    }

    @Test("Known hex values for lavender")
    func lavenderHexValues() {
        let bg = PastelColor.lavender.background
        // lavender background should be #C5B8F0
        #expect(bg.redComponent > 0.76 && bg.redComponent < 0.78)
        #expect(bg.greenComponent > 0.71 && bg.greenComponent < 0.73)
        #expect(bg.blueComponent > 0.93 && bg.blueComponent < 0.95)
    }

    @Test("Color names match raw values")
    func colorNamesMatchRawValues() {
        let names = PastelColor.allCases.map(\.rawValue)
        let expected = ["lavender", "mint", "peach", "sky", "rose", "lemon", "coral", "sage"]
        #expect(names == expected)
    }
}
