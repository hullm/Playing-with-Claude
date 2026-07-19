import Foundation
import Security

/// Thin wrapper around the macOS Keychain for storing the personal access token.
///
/// The token is stored as a generic password keyed by
/// (`AppConfig.keychainService`, `<environment>`), so switching between the dev
/// and prod servers keeps their tokens separate.
enum Keychain {
    /// Existence check only — queries metadata, not the secret data, so it does
    /// NOT trigger a Keychain access prompt. Use this instead of `token(for:)`
    /// when you only need to know whether a token is stored.
    static func hasToken(for environment: ServerEnvironment) -> Bool {
        var query = baseQuery(for: environment)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // No kSecReturnData → no decryption of the secret → no prompt.
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func token(for environment: ServerEnvironment) -> String? {
        var query: [String: Any] = baseQuery(for: environment)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    @discardableResult
    static func setToken(_ token: String, for environment: ServerEnvironment) -> Bool {
        let data = Data(token.utf8)

        // Try to update an existing item first; fall back to adding a new one.
        let query = baseQuery(for: environment)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }

        return false
    }

    @discardableResult
    static func deleteToken(for environment: ServerEnvironment) -> Bool {
        let status = SecItemDelete(baseQuery(for: environment) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(for environment: ServerEnvironment) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: environment.rawValue
        ]
    }
}
