import Foundation
import Testing
@testable import QuickMeeting
#if canImport(AppKit)
import AppKit
#endif

struct MeetingTranscriptContentTests {
    @Test
    func transcriptReloadKeyChangesWhenTranscriptPathChanges() throws {
        let meeting = Meeting(
            title: "Sync",
            startedAt: Date(timeIntervalSince1970: 1_714_561_200),
            status: .recorded,
            audioFilePath: "/tmp/audio.wav"
        )
        let initialKey = meetingTranscriptReloadKey(for: meeting)

        meeting.completeTranscription(
            transcript: StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(text: "Transcript", speakerID: "speaker-1")]
            ),
            transcriptPreview: "Transcript"
        )

        #expect(meetingTranscriptReloadKey(for: meeting) != initialKey)
    }

    @Test
    func audioReloadKeyDoesNotChangeWhenOnlyTranscriptChanges() throws {
        let meeting = Meeting(
            title: "Sync",
            startedAt: Date(timeIntervalSince1970: 1_714_561_200),
            status: .recorded,
            audioFilePath: "/tmp/audio.wav"
        )
        let initialKey = meetingAudioReloadKey(for: meeting)

        meeting.completeTranscription(
            transcript: StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(text: "Transcript", speakerID: "speaker-1")]
            ),
            transcriptPreview: "Transcript"
        )

        #expect(meetingAudioReloadKey(for: meeting) == initialKey)
    }

    @Test
    func missingTranscriptReturnsNotAvailable() throws {
        let content = loadMeetingTranscriptContent(from: nil)

        #expect(content == .notAvailable)
    }

    @Test
    func storedTranscriptRendersMarkdownFromStructuredData() {
        let content = loadMeetingTranscriptContent(
            from: StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Masha")],
                segments: [TranscriptSegment(text: "Hello world", speakerID: "speaker-1")]
            )
        )

        #expect(content == .text("## Masha\nHello world"))
    }

    @Test
    func meetingStoredTranscriptSortsPersistedSegmentsChronologically() throws {
        let meeting = Meeting(
            title: "Sync",
            startedAt: Date(timeIntervalSince1970: 1_714_561_200),
            status: .completed,
            audioFilePath: "/tmp/audio.wav",
            transcriptSpeakers: [PersistedTranscriptSpeaker(id: "speaker-1", displayName: "Masha")],
            transcriptSegments: [
                PersistedTranscriptSegment(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    text: "Second sentence",
                    startTime: 12,
                    endTime: 18,
                    speakerID: "speaker-1"
                ),
                PersistedTranscriptSegment(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    text: "First sentence",
                    startTime: 3,
                    endTime: 9,
                    speakerID: "speaker-1"
                ),
            ]
        )

        let transcript = try #require(meeting.storedTranscript)

        #expect(transcript.segments.map(\.text) == ["First sentence", "Second sentence"])
        #expect(loadMeetingTranscriptContent(from: transcript) == .text("## Masha\nFirst sentence\n\nSecond sentence"))
    }

    @Test
    func loadMeetingTranscriptSpeakersReturnsAvailableSpeakersFromStoredTranscript() {
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
        )

        let speakers = loadMeetingTranscriptSpeakers(from: transcript)

        #expect(speakers == .available([TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")]))
    }

    #if canImport(AppKit)
    @Test
    func transcriptAttributedStringPreservesTranscriptText() {
        let transcript = "## Speaker 1\nLine one\nLine two"

        let attributedString = makeTranscriptAttributedString(from: transcript)

        #expect(attributedString.string == transcript)
    }

    @Test
    func transcriptAttributedStringAppliesReadableLineSpacing() throws {
        let attributedString = makeTranscriptAttributedString(from: "Line one\nLine two")
        let paragraphStyle = try #require(
            attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )

        #expect(paragraphStyle.lineSpacing == 6)
    }
    #endif
}
