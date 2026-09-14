// ABOUTME: Tests for the short relative age shown beside titles: "now", "12m", "3h", "2d", then a date.
// ABOUTME: Worked examples against a fixed reference instant.

import Testing
import Foundation
@testable import Noter

@Suite("Age")
struct AgeTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Under a minute is now")
    func now_() { #expect(Age.short(now.addingTimeInterval(-20), relativeTo: now) == "now") }

    @Test("Minutes, hours, days")
    func units() {
        #expect(Age.short(now.addingTimeInterval(-12 * 60), relativeTo: now) == "12m")
        #expect(Age.short(now.addingTimeInterval(-3 * 3600 - 500), relativeTo: now) == "3h")
        #expect(Age.short(now.addingTimeInterval(-2 * 86400), relativeTo: now) == "2d")
    }

    @Test("Older than a week shows the calendar date")
    func date() {
        let old = now.addingTimeInterval(-10 * 86400)
        #expect(Age.short(old, relativeTo: now) == old.formatted(.dateTime.day().month(.abbreviated)))
    }
}
