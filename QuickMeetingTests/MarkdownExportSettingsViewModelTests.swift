import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct MarkdownExportSettingsViewModelTests {
    @Test
    func selectingDirectorySavesPathAndBackfillsExistingMeetings() throws {
        let suiteName = "MarkdownExportSettingsViewModelTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = MeetingMarkdownExportSettingsStore(userDefaults: defaults)
        let markdownExporter = ConfiguredMeetingMarkdownExporter(settingsStore: settingsStore)
        let harness = try Harness(markdownExporter: markdownExporter)
        let meeting = try harness.createCompletedMeeting()
        try harness.store.saveSummary(
            meetingID: meeting.id,
            summary: "Backfilled summary",
            updatedAt: Date(timeIntervalSince1970: 1_234_568_250)
        )
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickMeetingMarkdownExportSettings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)
        let viewModel = MarkdownExportSettingsViewModel(
            settingsStore: settingsStore,
            meetingStore: harness.store
        )

        viewModel.selectDirectory(exportURL)

        #expect(viewModel.directoryPath == exportURL.standardizedFileURL.path(percentEncoded: false))
        #expect(settingsStore.directoryPath() == viewModel.directoryPath)
        #expect(viewModel.errorMessage == nil)
        let exportedNames = try FileManager.default
            .contentsOfDirectory(atPath: exportURL.path)
            .sorted()
        #expect(exportedNames.contains { $0.hasSuffix(".transcript.md") && $0.contains(meeting.id.uuidString) })
        #expect(exportedNames.contains { $0.hasSuffix(".summary.md") && $0.contains(meeting.id.uuidString) })
    }

    @Test
    func selectingDirectoryClearsSettingAndRequestsReselectionWhenBackfillCannotAccessFolder() throws {
        let settingsStore = RecordingMarkdownExportSettingsStore()
        let harness = try Harness(markdownExporter: FailingMarkdownExporter())
        _ = try harness.createCompletedMeeting()
        let viewModel = MarkdownExportSettingsViewModel(settingsStore: settingsStore, meetingStore: harness.store)
        let exportURL = try temporaryExportDirectory()

        viewModel.selectDirectory(exportURL)

        #expect(viewModel.directoryPath.isEmpty)
        #expect(settingsStore.directoryPath() == nil)
        #expect(viewModel.errorMessage == MeetingMarkdownExporterError.exportDirectoryAccessUnavailable.errorDescription)
    }
}

private final class FailingMarkdownExporter: MeetingMarkdownExporting {
    func exportTranscript(for: Meeting, transcript: StoredTranscript) throws -> URL {
        throw MeetingMarkdownExporterError.exportDirectoryAccessUnavailable
    }

    func exportSummary(for: Meeting, summary: String) throws -> URL {
        throw MeetingMarkdownExporterError.exportDirectoryAccessUnavailable
    }

    func removeTranscript(for: UUID) throws {
        throw MeetingMarkdownExporterError.exportDirectoryAccessUnavailable
    }

    func removeSummary(for: UUID) throws {
        throw MeetingMarkdownExporterError.exportDirectoryAccessUnavailable
    }
}

private final class RecordingMarkdownExportSettingsStore: MeetingMarkdownExportSettingsStoring {
    private var storedURL: URL?

    func directoryPath() -> String? { storedURL?.path }

    func saveDirectoryPath(_ path: String?) {
        storedURL = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func directoryBookmarkData() -> Data? { nil }

    func saveDirectoryURL(_ url: URL) throws {
        storedURL = url.standardizedFileURL
    }

    func resolvedDirectoryURL() throws -> URL? { storedURL }
}

private func temporaryExportDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuickMeetingMarkdownExportSettingsTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private struct Harness {
    let container: ModelContainer
    let store: MeetingStore

    init(markdownExporter: any MeetingMarkdownExporting) throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        store = MeetingStore(modelContext: ModelContext(container), markdownExporter: markdownExporter)
    }

    func createCompletedMeeting() throws -> Meeting {
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let folderURL = URL(fileURLWithPath: "/tmp/meeting-\(UUID().uuidString)")
        let audioFileURL = folderURL.appendingPathComponent("audio.wav")
        let meeting = try store.createMeeting(
            title: "Design Review",
            startedAt: startedAt,
            attendeeNames: ["Alice", "Bob"],
            folderURL: folderURL,
            audioFileURL: audioFileURL
        )
        try store.finishRecording(meetingID: meeting.id, endedAt: startedAt.addingTimeInterval(60))
        try store.completeTranscription(
            meetingID: meeting.id,
            transcript: StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Alice")],
                segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
            ),
            transcriptPreview: "Hello",
            updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
        )
        return try store.fetchMeeting(id: meeting.id)
    }
}
