// ABOUTME: Runs background jobs a few at a time, keyed by note id, so a big inbox does not
// ABOUTME: launch one agent process per note. A job for an id already waiting or running is dropped.

import Foundation

public actor JobQueue {
    private let limit: Int
    private var running = 0
    private var inFlight: Set<UUID> = []
    private var waiting: [(id: UUID, name: String, work: @Sendable () async -> Void)] = []
    private var idle: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int) { self.limit = max(1, limit) }

    public func submit(id: UUID, name: String, work: @escaping @Sendable () async -> Void) {
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        waiting.append((id, name, work))
        pump()
    }

    /// Returns once every submitted job has finished. For tests.
    public func drain() async {
        guard running > 0 || !waiting.isEmpty else { return }
        await withCheckedContinuation { idle.append($0) }
    }

    private func pump() {
        while running < limit, !waiting.isEmpty {
            let job = waiting.removeFirst()
            running += 1
            Task {
                await job.work()
                await self.finished(job.id)
            }
        }
    }

    private func finished(_ id: UUID) {
        running -= 1
        inFlight.remove(id)
        pump()
        if running == 0, waiting.isEmpty {
            let waiters = idle; idle = []
            for w in waiters { w.resume() }
        }
    }
}
