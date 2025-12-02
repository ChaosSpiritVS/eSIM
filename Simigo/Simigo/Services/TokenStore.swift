import Foundation
import Security

actor TokenStore {
    static let shared = TokenStore()

    private let accessKey = "simigo.accessToken"
    private let refreshKey = "simigo.refreshToken"
    

    func setTokens(access: String, refresh: String) async {
        await save(key: accessKey, value: access)
        await save(key: refreshKey, value: refresh)
    }

    func getAccessToken() async -> String? {
        await load(key: accessKey)
    }

    func getRefreshToken() async -> String? {
        await load(key: refreshKey)
    }

    func clear() async {
        await delete(key: accessKey)
        await delete(key: refreshKey)
    }

    

    // MARK: - Keychain helpers
    private func save(key: String, value: String) async {
        let data = value.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func load(key: String) async -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func delete(key: String) async {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}