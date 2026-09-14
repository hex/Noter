// ABOUTME: Tests for ProcessRunner, which runs a CLI tool and collects its output.
// ABOUTME: Covers output larger than a pipe buffer, the deadline, and the exit status.

import Foundation
import Testing
@testable import Noter

@Suite("Process runner")
struct ProcessRunnerTests {
    @Test("Output bigger than the pipe buffer is drained while the tool runs")
    func largeOutput() async throws {
        let data = try await ProcessRunner.run(
            executable: "/bin/sh", arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' x"], timeout: 10
        )
        #expect(data.count == 300_000)
    }

    @Test("A tool that outlives the deadline is killed and reported as timed out")
    func deadline() async throws {
        let started = Date()
        await #expect(throws: EnricherError.timedOut) {
            try await ProcessRunner.run(executable: "/bin/sleep", arguments: ["30"], timeout: 0.3)
        }
        #expect(Date().timeIntervalSince(started) < 5)
        // The sleep must not survive the timeout.
        try await Task.sleep(for: .milliseconds(200))
        let ps = Process(); ps.executableURL = URL(fileURLWithPath: "/bin/sh")
        ps.arguments = ["-c", "pgrep -f '^/bin/sleep 30$' | wc -l"]
        let out = Pipe(); ps.standardOutput = out; try ps.run(); ps.waitUntilExit()
        let count = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(count == "0")
    }

    @Test("stderr is captured alongside stdout")
    func stderr() async throws {
        let data = try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "echo out; echo err 1>&2"], timeout: 10)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("out") && text.contains("err"))
    }
}
