import Foundation

enum UserDataManager {
    static func deleteAllUserData() throws {
        let fileManager = FileManager.default

        try clearContents(in: fileManager.urls(for: .documentDirectory, in: .userDomainMask).first)
        try clearContents(in: fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first)
        try clearContents(in: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        try clearContents(in: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))

        URLCache.shared.removeAllCachedResponses()

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
        UserDefaults.standard.synchronize()
    }

    private static func clearContents(in directory: URL?) throws {
        guard let directory else { return }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            try fileManager.removeItem(at: item)
        }
    }
}
