// ABOUTME: Runs a command-line tool to completion and returns everything it printed.
// ABOUTME: Output is drained while the tool runs, and a deadline kills a tool that hangs.

import Foundation

enum ProcessRunner {
    /// Runs `executable` and returns its combined stdout and stderr. Draining happens as bytes
    /// arrive, so a chatty tool cannot fill the pipe and block. After `timeout` seconds the tool
    /// is terminated and `EnricherError.timedOut` is thrown.
    static func run(executable: String, arguments: [String], environment: [String: String]? = nil, timeout: TimeInterval) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Read everything on a background thread; the reader returns at EOF, which comes after exit.
        let output = Task.detached(priority: .utility) { pipe.fileHandleForReading.readDataToEndOfFile() }
        let started = Date()
        try process.run()

        let exited = Task.detached(priority: .utility) { process.waitUntilExit() }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(timeout))
            process.terminate()
        }
        await exited.value
        watchdog.cancel()
        let timedOut = process.terminationReason == .uncaughtSignal && Date().timeIntervalSince(started) >= timeout
        let data = await output.value
        if timedOut { throw EnricherError.timedOut }
        return data
    }
}
