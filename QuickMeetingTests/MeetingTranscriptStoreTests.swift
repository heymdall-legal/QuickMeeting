import Foundation
import Testing
@testable import QuickMeeting

struct MeetingTranscriptStoreTests {
    @Test
    func renameSpeakerUpdatesSidecarAndRegeneratesMarkdown() throws {
        let fileManager = FileManager.default
        let meetingFolderURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: meetingFolderURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: meetingFolderURL) }

        let writer = TranscriptionArtifactWriter(fileManager: fileManager)
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello world", speakerID: "speaker-1")]
        )
        _ = try writer.writeArtifacts(for: transcript, in: meetingFolderURL)

        let store = MeetingTranscriptStore(fileManager: fileManager, artifactWriter: writer)
        let updated = try store.renameSpeaker(id: "speaker-1", to: "Masha", in: meetingFolderURL)

        let markdown = try String(
            contentsOf: meetingFolderURL.appendingPathComponent("transcript.md"),
            encoding: .utf8
        )
        #expect(updated.speakers.first?.displayName == "Masha")
        #expect(markdown == "## Masha\nHello world")
    }

    @Test
    func renameSpeakerFailsWhenSidecarIsMissing() throws {
        let fileManager = FileManager.default
        let meetingFolderURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: meetingFolderURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: meetingFolderURL) }

        let store = MeetingTranscriptStore(fileManager: fileManager)

        #expect(throws: MeetingTranscriptStoreError.sidecarMissing) {
            try store.renameSpeaker(id: "speaker-1", to: "Masha", in: meetingFolderURL)
        }
    }
}
