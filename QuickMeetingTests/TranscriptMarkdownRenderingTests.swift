import Foundation
import Testing
@testable import QuickMeeting

struct TranscriptMarkdownRenderingTests {
    @Test
    func storedTranscriptCapturesSpeakersAndSegments() {
        let transcript = StoredTranscript(
            speakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
                TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2"),
            ],
            segments: [
                TranscriptSegment(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    text: "Hello everyone.",
                    startTime: 0,
                    endTime: 1.2,
                    speakerID: "speaker-1"
                ),
                TranscriptSegment(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    text: "Thanks, let's start.",
                    startTime: 1.3,
                    endTime: 2.4,
                    speakerID: "speaker-2"
                ),
            ]
        )

        #expect(transcript.speakers.map(\.displayName) == ["Speaker 1", "Speaker 2"])
        #expect(transcript.segments.map(\.speakerID) == ["speaker-1", "speaker-2"])
        #expect(transcript.fullText == "Hello everyone.\nThanks, let's start.")
    }

    @Test
    func renderMarkdownGroupsConsecutiveSegmentsBySpeaker() {
        let writer = TranscriptionArtifactWriter(fileManager: .default)
        let transcript = StoredTranscript(
            speakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
                TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2"),
            ],
            segments: [
                TranscriptSegment(text: "Hello everyone.", startTime: 0, endTime: 1, speakerID: "speaker-1"),
                TranscriptSegment(text: "One more point.", startTime: 1, endTime: 2, speakerID: "speaker-1"),
                TranscriptSegment(text: "Thanks, let's start.", startTime: 2, endTime: 3, speakerID: "speaker-2"),
            ]
        )

        let markdown = writer.renderMarkdown(from: transcript)

        #expect(markdown == """
        ## Speaker 1
        Hello everyone.

        One more point.

        ## Speaker 2
        Thanks, let's start.
        """)
    }
}
