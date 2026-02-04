import Foundation
import Security

final class CredentialStore {
    private let keychain = KeychainHelper()
    private let defaults = UserDefaults.standard
    private let stateKey = "smart_state"
    private let verifierKey = "smart_code_verifier"

    func saveState(_ value: String) {
        save(value, for: stateKey)
    }

    func loadState() -> String? {
        load(stateKey)
    }

    func saveCodeVerifier(_ value: String) {
        save(value, for: verifierKey)
    }

    func loadCodeVerifier() -> String? {
        load(verifierKey)
    }

    private func save(_ value: String, for key: String) {
        if !keychain.save(value, for: key) {
            defaults.set(value, forKey: key)
        }
    }

    private func load(_ key: String) -> String? {
        keychain.read(key) ?? defaults.string(forKey: key)
    }
}

final class KeychainHelper {
    private let service = "com.example.smartfhir"

    func save(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = query.merging(
            [kSecValueData as String: data],
            uniquingKeysWith: { $1 }
        )

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }
}
