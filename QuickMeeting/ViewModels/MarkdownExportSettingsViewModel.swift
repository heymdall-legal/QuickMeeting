import Combine
import Foundation

@MainActor
final class MarkdownExportSettingsViewModel: ObservableObject {
    @Published private(set) var directoryPath: String
    @Published private(set) var errorMessage: String?

    private let settingsStore: any MeetingMarkdownExportSettingsStoring
    private let meetingStore: MeetingStore

    init(
        settingsStore: any MeetingMarkdownExportSettingsStoring,
        meetingStore: MeetingStore
    ) {
        self.settingsStore = settingsStore
        self.meetingStore = meetingStore
        directoryPath = settingsStore.directoryPath() ?? ""
    }

    var hasDirectory: Bool {
        !directoryPath.isEmpty
    }

    var displayPath: String {
        directoryPath.isEmpty ? "No folder selected" : directoryPath
    }

    func selectDirectory(_ url: URL) {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try settingsStore.saveDirectoryURL(url)
            directoryPath = path
            try meetingStore.exportMarkdownForExistingMeetings()
            errorMessage = nil
        } catch {
            settingsStore.saveDirectoryPath(nil)
            directoryPath = ""
            errorMessage = error.localizedDescription
        }
    }

    func clearDirectory() {
        settingsStore.saveDirectoryPath(nil)
        directoryPath = ""
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }
}
