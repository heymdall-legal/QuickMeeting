import Foundation
import Testing
@testable import QuickMeeting

struct MeetingTranscriptContentTests {
    @Test
    func detailReloadKeyChangesWhenTranscriptPathChanges() throws {
        let meeting = Meeting(
            title: "Sync",
            startedAt: Date(timeIntervalSince1970: 1_714_561_200),
            status: .recorded,
            audioFilePath: "/tmp/audio.wav"
        )
        let initialKey = meetingDetailReloadKey(for: meeting)

        meeting.completeTranscription(
            transcriptFilePath: "/tmp/transcript.md",
            transcriptPreview: "Transcript"
        )

        #expect(meetingDetailReloadKey(for: meeting) != initialKey)
    }

    @Test
    func missingTranscriptPathReturnsNotAvailable() throws {
        let content = try loadMeetingTranscriptContent(from: nil)

        #expect(content == .notAvailable)
    }

    @Test
    func readableMarkdownTranscriptFileReturnsText() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let transcriptURL = rootURL.appendingPathComponent("transcript.md")
        try "## Speaker 1\nLine one".write(to: transcriptURL, atomically: true, encoding: .utf8)

        let content = try loadMeetingTranscriptContent(from: transcriptURL.path)

        #expect(content == .text("## Speaker 1\nLine one"))
    }

    @Test
    func percentEncodedTranscriptPathResolvesToFilesystemPath() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("Quick Meeting \(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let transcriptURL = rootURL.appendingPathComponent("transcript file.md")
        try "Transcript body".write(to: transcriptURL, atomically: true, encoding: .utf8)

        let content = try loadMeetingTranscriptContent(
            from: transcriptURL.path(percentEncoded: true)
        )

        #expect(content == .text("Transcript body"))
    }

    @Test
    func unreadableTranscriptPathReturnsUnavailable() throws {
        let fileManager = FileManager.default
        let missingPath = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("missing-transcript.md")
            .path

        let content = try loadMeetingTranscriptContent(from: missingPath)

        #expect(content == .unavailable(message: "Transcript file is unavailable."))
    }

    @Test
    func loadMeetingTranscriptSpeakersReturnsAvailableSpeakersWhenSidecarExists() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let writer = TranscriptionArtifactWriter(fileManager: fileManager)
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
        )
        let artifacts = try writer.writeArtifacts(for: transcript, in: rootURL)

        let speakers = loadMeetingTranscriptSpeakers(from: artifacts.transcriptFileURL.path, fileManager: fileManager)

        #expect(speakers == .available([TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")]))
    }
}
