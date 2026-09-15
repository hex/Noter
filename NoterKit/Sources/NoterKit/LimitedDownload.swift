// ABOUTME: Downloads a response but stops reading at a byte cap, so a huge page or image costs
// ABOUTME: at most the cap in bandwidth and memory instead of arriving whole and then being cut.

import Foundation

public enum LimitedDownload {
    public struct Result {
        public var data: Data
        public var truncated: Bool
        public var response: URLResponse
    }

    public static func fetch(_ request: URLRequest, limit: Int, session: URLSession = .shared) async throws -> Result {
        let (bytes, response) = try await session.bytes(for: request)
        var data = Data()
        data.reserveCapacity(min(limit, Int(max(0, response.expectedContentLength))))
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { return Result(data: data, truncated: true, response: response) }
        }
        return Result(data: data, truncated: false, response: response)
    }
}
