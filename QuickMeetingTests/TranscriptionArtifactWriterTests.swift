import Foundation
import Testing
@testable import QuickMeeting

struct TranscriptionArtifactWriterTests {
    @Test
    func writeArtifactsPersistsStructuredAndMarkdownTranscript() throws {
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

        let artifacts = try writer.writeArtifacts(for: transcript, in: meetingFolderURL)

        #expect(artifacts.transcriptFileURL == meetingFolderURL.appendingPathComponent("transcript.md"))
        #expect(artifacts.sidecarFileURL == meetingFolderURL.appendingPathComponent("transcript.json"))
        #expect(try String(contentsOf: artifacts.transcriptFileURL, encoding: .utf8) == "## Speaker 1\nHello world")
        #expect(artifacts.previewText == "Hello world")
    }

    @Test
    func previewIsTrimmedFromStructuredTranscriptText() {
        let writer = TranscriptionArtifactWriter()
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [
                TranscriptSegment(text: "  First sentence.  ", speakerID: "speaker-1"),
                TranscriptSegment(text: "Second sentence.", speakerID: "speaker-1"),
            ]
        )

        #expect(writer.makePreviewText(from: transcript) == "First sentence.\nSecond sentence.")
    }
}
