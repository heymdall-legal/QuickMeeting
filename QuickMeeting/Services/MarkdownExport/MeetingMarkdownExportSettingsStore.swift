import Foundation

protocol MeetingMarkdownExportSettingsStoring {
    func directoryPath() -> String?
    func saveDirectoryPath(_ path: String?)
    func directoryBookmarkData() -> Data?
    func saveDirectoryURL(_ url: URL) throws
    func resolvedDirectoryURL() throws -> URL?
}

struct MeetingMarkdownExportSettingsStore: MeetingMarkdownExportSettingsStoring {
    private let userDefaults: UserDefaults
    private let directoryPathKey = "meetingMarkdownExport.directoryPath"
    private let directoryBookmarkDataKey = "meetingMarkdownExport.directoryBookmarkData"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func directoryPath() -> String? {
        userDefaults.string(forKey: directoryPathKey)
    }

    func saveDirectoryPath(_ path: String?) {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            userDefaults.removeObject(forKey: directoryPathKey)
            userDefaults.removeObject(forKey: directoryBookmarkDataKey)
            return
        }

        userDefaults.set(path, forKey: directoryPathKey)
    }

    func directoryBookmarkData() -> Data? {
        userDefaults.data(forKey: directoryBookmarkDataKey)
    }

    func saveDirectoryURL(_ url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        let bookmarkData = try standardizedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        userDefaults.set(
            standardizedURL.path(percentEncoded: false),
            forKey: directoryPathKey
        )
        userDefaults.set(bookmarkData, forKey: directoryBookmarkDataKey)
    }

    func resolvedDirectoryURL() throws -> URL? {
        guard let bookmarkData = directoryBookmarkData() else {
            return directoryPath().map { URL(fileURLWithPath: $0, isDirectory: true) }
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return url.standardizedFileURL
    }
}
