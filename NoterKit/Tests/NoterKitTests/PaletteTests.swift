// ABOUTME: Tests for the palette names: completeness, order, and cycling.
// ABOUTME: Colour values are tested in each app's theme tests.

import Testing
@testable import NoterKit

@Suite("Palette")
struct PaletteTests {
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
}
