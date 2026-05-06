import Foundation
import Testing
@testable import QuickMeeting

struct TranscriptionArtifactWriterTests {
    @Test
    func writeArtifactsPersistsTranscriptTextNextToMeetingAudio() throws {
        let fileManager = FileManager.default
        let meetingFolderURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: meetingFolderURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: meetingFolderURL) }

        let writer = TranscriptionArtifactWriter(fileManager: fileManager)
        let result = TranscriptionResult(
            fullText: "Hello world",
            segments: [
                TranscriptSegment(text: "Hello"),
                TranscriptSegment(text: "world"),
            ]
        )

        let artifacts = try writer.writeArtifacts(for: result, in: meetingFolderURL)

        #expect(artifacts.transcriptFileURL == meetingFolderURL.appendingPathComponent("transcript.txt"))
        #expect(try String(contentsOf: artifacts.transcriptFileURL) == "Hello world")
        #expect(artifacts.previewText == "Hello world")
    }

    @Test
    func previewIsTrimmedFromStructuredResultText() {
        let writer = TranscriptionArtifactWriter()
        let result = TranscriptionResult(
            fullText: "  First sentence.\nSecond sentence.  ",
            segments: []
        )

        #expect(writer.makePreviewText(from: result) == "First sentence.\nSecond sentence.")
    }
}
