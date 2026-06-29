import Foundation

protocol MeetingMarkdownExportSettingsStoring {
    func directoryPath() -> String?
    func saveDirectoryPath(_ path: String?)
}

struct MeetingMarkdownExportSettingsStore: MeetingMarkdownExportSettingsStoring {
    private let userDefaults: UserDefaults
    private let directoryPathKey = "meetingMarkdownExport.directoryPath"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func directoryPath() -> String? {
        userDefaults.string(forKey: directoryPathKey)
    }

    func saveDirectoryPath(_ path: String?) {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            userDefaults.removeObject(forKey: directoryPathKey)
            return
        }

        userDefaults.set(path, forKey: directoryPathKey)
    }
}
