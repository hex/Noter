// ABOUTME: Coalesces a burst of triggers into one call after a quiet period.
// ABOUTME: Each trigger replaces the pending call, so ten filesystem events cost one sweep.

import Foundation

@MainActor
final class Debounce {
    private let delay: TimeInterval
    private let action: @MainActor () -> Void
    private var pending: DispatchWorkItem?

    init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.delay = delay
        self.action = action
    }

    func trigger() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.action() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
