// ABOUTME: API keys per provider, kept in the login keychain under service "Noter" (account = provider),
// ABOUTME: with the provider's environment variable as a fallback when Noter is launched from a shell.

import Foundation
import Security

enum APIProvider: String, CaseIterable {
    case anthropic, openai, gemini

    var environmentVariables: [String] {
        switch self {
        case .anthropic: ["ANTHROPIC_API_KEY"]
        case .openai: ["OPENAI_API_KEY"]
        case .gemini: ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
        }
    }
}

enum APIKey {
    private static func query(_ provider: APIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Noter",
            kSecAttrAccount as String: provider.rawValue,
        ]
    }

    /// Keychain first, then the environment.
    static func load(_ provider: APIProvider) -> String? {
        stored(provider) ?? fromEnvironment(provider)
    }

    static func fromEnvironment(_ provider: APIProvider) -> String? {
        let env = ProcessInfo.processInfo.environment
        return provider.environmentVariables.lazy.compactMap { env[$0] }.first { !$0.isEmpty }
    }

    static func stored(_ provider: APIProvider) -> String? {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func save(_ key: String, for provider: APIProvider) {
        SecItemDelete(query(provider) as CFDictionary)
        guard !key.isEmpty else { return }
        var q = query(provider)
        q[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
