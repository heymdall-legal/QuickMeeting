import Foundation
import Testing
@testable import QuickMeeting

struct MeetingSearchTests {
    @Test
    func emptyAndWhitespaceQueriesDoNotFilterMeeting() {
        let meeting = makeMeeting(title: "Weekly Product Sync")

        #expect(meetingMatchesSearch(meeting, query: ""))
        #expect(meetingMatchesSearch(meeting, query: "   \n"))
    }

    @Test
    func titleMatchesContiguousPhraseCaseInsensitively() {
        let meeting = makeMeeting(title: "Weekly Design Review")

        #expect(meetingMatchesSearch(meeting, query: "  DESIGN review  "))
        #expect(!meetingMatchesSearch(meeting, query: "design weekly"))
    }

    @Test
    func namedTranscriptSpeakerMatchesCaseInsensitively() {
        let meeting = makeMeeting(
            speakers: [
                PersistedTranscriptSpeaker(id: "speaker-1", displayName: "Masha Ivanova")
            ]
        )

        #expect(meetingMatchesSearch(meeting, query: "masha iva"))
    }

    @Test
    func placeholderTranscriptSpeakerDoesNotMatch() {
        let meeting = makeMeeting(
            speakers: [
                PersistedTranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")
            ]
        )

        #expect(!meetingMatchesSearch(meeting, query: "speaker 1"))
    }

    @Test
    func calendarAttendeeDoesNotMatch() {
        let meeting = makeMeeting(attendeeNames: ["Calendar Person"])

        #expect(!meetingMatchesSearch(meeting, query: "calendar person"))
    }

    @Test
    func transcriptSegmentMatchesContiguousPhraseCaseInsensitively() {
        let meeting = makeMeeting(
            segments: [
                PersistedTranscriptSegment(TranscriptSegment(
                    text: "The design review went well",
                    speakerID: "speaker-1"
                ))
            ]
        )

        #expect(meetingMatchesSearch(meeting, query: "DESIGN review"))
    }

    @Test
    func multiwordQueryDoesNotMatchSeparatedWordsWithinOneSegment() {
        let meeting = makeMeeting(
            segments: [
                PersistedTranscriptSegment(TranscriptSegment(
                    text: "Design decisions from the quarterly review",
                    speakerID: "speaker-1"
                ))
            ]
        )

        #expect(!meetingMatchesSearch(meeting, query: "design review"))
    }

    @Test
    func queryDoesNotCombineMatchesAcrossFieldsOrSegments() {
        let meeting = makeMeeting(
            title: "Design",
            segments: [
                PersistedTranscriptSegment(TranscriptSegment(text: "Review", speakerID: "speaker-1")),
                PersistedTranscriptSegment(TranscriptSegment(text: "Design", speakerID: "speaker-1"))
            ]
        )

        #expect(!meetingMatchesSearch(meeting, query: "design review"))
    }

    @Test
    func meetingWithoutTranscriptStillSearchesByTitleSafely() {
        let meeting = makeMeeting(title: "Roadmap Planning")

        #expect(meeting.storedTranscript == nil)
        #expect(meetingMatchesSearch(meeting, query: "roadmap"))
        #expect(!meetingMatchesSearch(meeting, query: "budget"))
    }

    private func makeMeeting(
        title: String = "Unrelated Meeting",
        speakers: [PersistedTranscriptSpeaker] = [],
        segments: [PersistedTranscriptSegment] = [],
        attendeeNames: [String] = []
    ) -> Meeting {
        Meeting(
            title: title,
            startedAt: Date(timeIntervalSince1970: 1_714_561_200),
            status: .completed,
            audioFilePath: "/tmp/audio.wav",
            transcriptSpeakers: speakers,
            transcriptSegments: segments,
            attendeeNames: attendeeNames
        )
    }
}
