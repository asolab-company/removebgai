import FirebaseCore
import FirebaseRemoteConfig
import Foundation

enum OpenAIAPIKeyError: LocalizedError {
    case firebaseNotConfigured
    case emptyKey

    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            return "Firebase configuration is missing or does not match this app."
        case .emptyKey:
            return "AI editing is temporarily unavailable. Please try again later."
        }
    }
}
@MainActor
final class OpenAIAPIKeyManager {
    static let shared = OpenAIAPIKeyManager()
    private static let parameterName = "OPENAI_API_KEY"
    private var refreshTask: Task<String, Error>?

    private init() {}

    func apiKey() async throws -> String {
        try await refreshKey()
    }

    func refreshKeyIfNeeded() async {
        _ = try? await refreshKey()
    }

    private func refreshKey() async throws -> String {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard FirebaseApp.app() != nil else {
            throw OpenAIAPIKeyError.firebaseNotConfigured
        }

        let task = Task<String, Error> {
            let config = RemoteConfig.remoteConfig()
            let settings = RemoteConfigSettings()
            #if DEBUG
            settings.minimumFetchInterval = 0
            #else
            settings.minimumFetchInterval = 6 * 60 * 60
            #endif
            settings.fetchTimeout = 12
            config.configSettings = settings

            do {
                _ = try await config.fetchAndActivate()
            } catch {
                guard Self.activeKey(in: config) != nil else { throw error }
            }
            guard let key = Self.activeKey(in: config) else {
                throw OpenAIAPIKeyError.emptyKey
            }
            return key
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private static func activeKey(in config: RemoteConfig) -> String? {
        let value = config.configValue(forKey: parameterName)
        guard value.source == .remote else { return nil }
        let key = value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }
}
