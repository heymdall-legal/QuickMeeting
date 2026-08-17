import Foundation
import Testing
@testable import QuickMeeting

struct MeetingMarkdownExportSettingsStoreTests {
    @Test
    func persistsSelectedDirectoryPath() {
        let suiteName = "MeetingMarkdownExportSettingsStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = MeetingMarkdownExportSettingsStore(userDefaults: defaults)

        store.saveDirectoryPath("/Users/leo/Vault/Meetings")

        #expect(store.directoryPath() == "/Users/leo/Vault/Meetings")

        store.saveDirectoryPath(nil)

        #expect(store.directoryPath() == nil)
    }

    @Test
    func persistsSecurityScopedBookmarkForSelectedDirectory() throws {
        let suiteName = "MeetingMarkdownExportSettingsStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = MeetingMarkdownExportSettingsStore(userDefaults: defaults)
        let directoryURL = try temporaryExportDirectory()

        try store.saveDirectoryURL(directoryURL)

        #expect(store.directoryPath() == directoryURL.standardizedFileURL.path(percentEncoded: false))
        #expect(store.directoryBookmarkData() != nil)
        #expect(try store.resolvedDirectoryURL()?.standardizedFileURL == directoryURL.standardizedFileURL)

        store.saveDirectoryPath(nil)

        #expect(store.directoryBookmarkData() == nil)
    }
}

struct MeetingMarkdownExporterTests {
    @Test
    func exportsTranscriptWithObsidianFrontmatterAndSpeakerSections() throws {
        let rootURL = try temporaryExportDirectory()
        let exporter = MeetingMarkdownExporter(rootURL: rootURL)
        let meetingID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let meeting = makeMeeting(
            id: meetingID,
            title: "Design: Review / Launch",
            attendeeNames: ["Masha", "Ilya"],
            summaryText: nil
        )
        let transcript = StoredTranscript(
            speakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Masha"),
                TranscriptSpeaker(id: "speaker-2", displayName: "Ilya"),
            ],
            segments: [
                TranscriptSegment(text: "We approved the launch checklist.", speakerID: "speaker-1"),
                TranscriptSegment(text: "I will publish the notes.", speakerID: "speaker-2"),
            ]
        )

        let fileURL = try exporter.exportTranscript(for: meeting, transcript: transcript)

        #expect(fileURL.lastPathComponent == "2009-02-14 Design Review Launch 11111111-1111-1111-1111-111111111111.transcript.md")
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(markdown.contains("type: transcript"))
        #expect(markdown.contains("id: \"11111111-1111-1111-1111-111111111111\""))
        #expect(markdown.contains("title: \"Design: Review / Launch\""))
        #expect(markdown.contains("attendees:"))
        #expect(markdown.contains("  - \"Masha\""))
        #expect(markdown.contains("source_audio: \"/tmp/quickmeeting-audio/audio.m4a\""))
        #expect(markdown.contains("# Design: Review / Launch"))
        #expect(markdown.contains("## Transcript"))
        #expect(markdown.contains("### Masha"))
        #expect(markdown.contains("We approved the launch checklist."))
        #expect(markdown.contains("### Ilya"))
        #expect(markdown.contains("I will publish the notes."))
    }

    @Test
    func exportsSummaryAndReplacesExistingFileForSameMeetingAndType() throws {
        let rootURL = try temporaryExportDirectory()
        let exporter = MeetingMarkdownExporter(rootURL: rootURL)
        let meetingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let staleURL = rootURL
            .appendingPathComponent("2009-02-14 Original Name 22222222-2222-2222-2222-222222222222.summary.md")
        try "stale".write(to: staleURL, atomically: true, encoding: .utf8)

        let renamed = makeMeeting(id: meetingID, title: "Renamed Name", summaryText: "New summary")
        let fileURL = try exporter.exportSummary(for: renamed, summary: "New summary")

        #expect(fileURL.lastPathComponent == "2009-02-14 Renamed Name 22222222-2222-2222-2222-222222222222.summary.md")
        #expect(!FileManager.default.fileExists(atPath: staleURL.path))
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(markdown.contains("type: summary"))
        #expect(markdown.contains("# Renamed Name"))
        #expect(markdown.contains("## Summary"))
        #expect(markdown.contains("New summary"))
        #expect(!markdown.contains("stale"))
    }

    @Test
    func configuredExporterUsesPersistedDirectoryBookmark() throws {
        let suiteName = "MeetingMarkdownExporterTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = MeetingMarkdownExportSettingsStore(userDefaults: defaults)
        let rootURL = try temporaryExportDirectory()
        try settingsStore.saveDirectoryURL(rootURL)
        let exporter = ConfiguredMeetingMarkdownExporter(settingsStore: settingsStore)
        let meetingID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let meeting = makeMeeting(id: meetingID, title: "Scoped Folder", summaryText: "Summary")

        let fileURL = try exporter.exportSummary(for: meeting, summary: "Summary")

        #expect(fileURL.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test
    func configuredExporterRejectsDirectoryWhenScopedAccessCannotStart() throws {
        let rootURL = try temporaryExportDirectory()
        let settingsStore = InMemoryMarkdownExportSettingsStore(directoryURL: rootURL)
        let exporter = ConfiguredMeetingMarkdownExporter(
            settingsStore: settingsStore,
            startAccessingSecurityScopedResource: { _ in false },
            stopAccessingSecurityScopedResource: { _ in Issue.record("Must not stop access that did not start") }
        )

        #expect(throws: MeetingMarkdownExporterError.exportDirectoryAccessUnavailable) {
            try exporter.exportSummary(
                for: makeMeeting(id: UUID(), title: "Unavailable Folder", summaryText: "Summary"),
                summary: "Summary"
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: rootURL.path).isEmpty)
    }
}

private struct InMemoryMarkdownExportSettingsStore: MeetingMarkdownExportSettingsStoring {
    let directoryURL: URL?

    func directoryPath() -> String? { directoryURL?.path }
    func saveDirectoryPath(_: String?) {}
    func directoryBookmarkData() -> Data? { nil }
    func saveDirectoryURL(_: URL) throws {}
    func resolvedDirectoryURL() throws -> URL? { directoryURL }
}

private func temporaryExportDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuickMeetingMarkdownExporterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeMeeting(
    id: UUID,
    title: String,
    attendeeNames: [String] = [],
    summaryText: String?
) -> Meeting {
    Meeting(
        id: id,
        title: title,
        startedAt: Date(timeIntervalSince1970: 1_234_612_800),
        endedAt: Date(timeIntervalSince1970: 1_234_613_100),
        status: .completed,
        audioFilePath: "/tmp/quickmeeting-audio/audio.m4a",
        summaryText: summaryText,
        duration: 300,
        attendeeNames: attendeeNames,
        createdAt: Date(timeIntervalSince1970: 1_234_612_700),
        updatedAt: Date(timeIntervalSince1970: 1_234_613_200)
    )
}
