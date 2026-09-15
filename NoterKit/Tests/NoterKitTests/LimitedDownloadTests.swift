// ABOUTME: Tests for limited downloads: bytes stop arriving at the cap instead of after the whole body.
// ABOUTME: Uses file URLs so no network is involved.

import Foundation
import Testing
@testable import NoterKit

@Suite("Limited download")
struct LimitedDownloadTests {
    private func file(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Limited-\(UUID().uuidString).bin")
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    @Test("A body under the cap arrives whole")
    func whole() async throws {
        let result = try await LimitedDownload.fetch(URLRequest(url: try file(bytes: 1000)), limit: 4096)
        #expect(result.data.count == 1000)
        #expect(!result.truncated)
    }

    @Test("A body over the cap is cut at the cap and flagged")
    func truncated() async throws {
        let result = try await LimitedDownload.fetch(URLRequest(url: try file(bytes: 300_000)), limit: 65_536)
        #expect(result.data.count == 65_536)
        #expect(result.truncated)
    }
}
