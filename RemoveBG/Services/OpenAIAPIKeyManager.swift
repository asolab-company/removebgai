import Foundation
import Security

enum OpenAIAPIKeyError: LocalizedError {
    case invalidRemoteURL
    case invalidResponse
    case emptyKey
    case keychainSaveFailed(OSStatus)
    case keychainReadFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidRemoteURL:
            return "OpenAI key URL is invalid."
        case .invalidResponse:
            return "Could not load the OpenAI key."
        case .emptyKey:
            return "OpenAI key is empty."
        case .keychainSaveFailed:
            return "Could not save the OpenAI key."
        case .keychainReadFailed:
            return "Could not read the OpenAI key."
        }
    }
}

actor OpenAIAPIKeyManager {
    nonisolated static let shared = OpenAIAPIKeyManager()

    private let remoteURL = URL(string: "https://pastebin.com/raw/FL11Ea5X")
    private let keychainService = "com.dev.RemoveBG.openai"
    private let keychainAccount = "apiKey"
    private let refreshInterval: TimeInterval = 6 * 60 * 60
    private let lastRefreshKey = "openai_api_key_last_refresh"
    private var inMemoryKey: String?
    private var isRefreshing = false

    func apiKey() async throws -> String {
        if let inMemoryKey, !inMemoryKey.isEmpty {
            return inMemoryKey
        }

        if let cachedKey = try cachedKey(), !cachedKey.isEmpty {
            inMemoryKey = cachedKey
            return cachedKey
        }

        try await refreshKey(force: true)

        let refreshedKey: String?
        if let inMemoryKey {
            refreshedKey = inMemoryKey
        } else {
            refreshedKey = try cachedKey()
        }
        guard let refreshedKey, !refreshedKey.isEmpty else {
            throw OpenAIAPIKeyError.emptyKey
        }

        return refreshedKey
    }

    func refreshKeyIfNeeded() async {
        do {
            let shouldRefresh = await shouldRefreshKey()
            guard shouldRefresh else {
                inMemoryKey = try cachedKey()
                return
            }
            try await refreshKey(force: false)
        } catch {
        }
    }

    func refreshKey(force: Bool) async throws {
        if isRefreshing {
            return
        }

        if !force, !(await shouldRefreshKey()) {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        guard let remoteURL else {
            throw OpenAIAPIKeyError.invalidRemoteURL
        }

        let request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw OpenAIAPIKeyError.invalidResponse
        }

        guard let fetchedKey = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !fetchedKey.isEmpty
        else {
            throw OpenAIAPIKeyError.emptyKey
        }

        try saveKey(fetchedKey)
        inMemoryKey = fetchedKey
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRefreshKey)
    }

    private func shouldRefreshKey() async -> Bool {
        if inMemoryKey == nil {
            inMemoryKey = try? cachedKey()
        }

        guard inMemoryKey?.isEmpty == false else {
            return true
        }

        let lastRefresh = UserDefaults.standard.double(forKey: lastRefreshKey)
        guard lastRefresh > 0 else {
            return true
        }

        return Date().timeIntervalSince1970 - lastRefresh > refreshInterval
    }

    private func cachedKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw OpenAIAPIKeyError.keychainReadFailed(status)
        }
        guard
            let data = result as? Data,
            let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return key
    }

    private func saveKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw OpenAIAPIKeyError.keychainSaveFailed(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OpenAIAPIKeyError.keychainSaveFailed(addStatus)
        }
    }
}
