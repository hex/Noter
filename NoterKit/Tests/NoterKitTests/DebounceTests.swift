// ABOUTME: Tests for Debounce, which coalesces a burst of triggers into one call after a quiet period.
// ABOUTME: A second trigger during the wait must replace the first, not add to it.

import Foundation
import Testing
@testable import NoterKit

@Suite("Debounce")
struct DebounceTests {
    @Test("A burst of triggers produces one call")
    @MainActor
    func coalesces() async throws {
        var calls = 0
        let debounce = Debounce(delay: 0.05) { calls += 1 }
        for _ in 0..<5 { debounce.trigger() }
        try await Task.sleep(for: .milliseconds(150))
        #expect(calls == 1)
    }

    @Test("Triggers spaced beyond the delay each produce a call")
    @MainActor
    func separate() async throws {
        var calls = 0
        let debounce = Debounce(delay: 0.03) { calls += 1 }
        debounce.trigger()
        try await Task.sleep(for: .milliseconds(80))
        debounce.trigger()
        try await Task.sleep(for: .milliseconds(80))
        #expect(calls == 2)
    }
}
