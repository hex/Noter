// ABOUTME: Tests for JobQueue, which bounds how many enrichment jobs run at once.
// ABOUTME: Checks the concurrency cap and that a job already in flight is not started twice.

import Foundation
import Testing
@testable import Noter

@Suite("Job queue")
struct JobQueueTests {
    actor Counter {
        var running = 0
        var peak = 0
        var started = 0
        func enter() { running += 1; peak = max(peak, running); started += 1 }
        func leave() { running -= 1 }
    }

    @Test("Never more than the limit run at once")
    func cap() async throws {
        let queue = JobQueue(limit: 2)
        let counter = Counter()
        for i in 0..<6 {
            await queue.submit(id: UUID(), name: "job\(i)") {
                await counter.enter()
                try? await Task.sleep(for: .milliseconds(40))
                await counter.leave()
            }
        }
        await queue.drain()
        #expect(await counter.peak == 2)
        #expect(await counter.started == 6)
    }

    @Test("A job for an id already queued or running is dropped")
    func dedupe() async throws {
        let queue = JobQueue(limit: 1)
        let counter = Counter()
        let id = UUID()
        for _ in 0..<3 {
            await queue.submit(id: id, name: "same") {
                await counter.enter()
                try? await Task.sleep(for: .milliseconds(30))
                await counter.leave()
            }
        }
        await queue.drain()
        #expect(await counter.started == 1)
    }
}
