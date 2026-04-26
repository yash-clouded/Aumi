import Foundation
import Security

/// Persists the AES-256 session key and paired device info in the macOS Keychain.
enum KeychainStore {

    private static let service = "com.aumi.app"

    // MARK: - Session Key

    static func saveSessionKey(_ key: Data) {
        save(key: "session_key", value: key)
    }

    static func loadSessionKey() -> Data? {
        load(key: "session_key")
    }

    static func savePeerId(_ id: String) {
        guard let data = id.data(using: .utf8) else { return }
        save(key: "peer_id", value: data)
    }

    static func loadPeerId() -> String? {
        guard let data = load(key: "peer_id") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func isPaired() -> Bool {
        return loadSessionKey() != nil
    }

    static func clearPairing() {
        delete(key: "session_key")
        delete(key: "peer_id")
    }

    // MARK: - Private Keychain Accessors

    private static func save(key: String, value: Data) {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        value,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func load(key: String) -> Data? {
        var result: AnyObject?
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    private static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
