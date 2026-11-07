import Foundation
import Security

/// Stores the GitHub token in the keychain instead of `UserDefaults`, so it
/// is not part of a backup in clear text and not readable by other apps.
enum GitHubTokenStore {
    private static let service = "com.beretdt.GooseIDE.github"
    private static let account = "token"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ token: String) {
        delete()
        guard !token.isEmpty else { return }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
