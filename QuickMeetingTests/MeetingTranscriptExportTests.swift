import Foundation
import Testing
@testable import QuickMeeting

struct MeetingTranscriptExportTests {
    @Test
    func exportMarkdownIncludesMeetingHeaderAndGroupedSpeakerSections() {
        let meeting = Meeting(
            title: "Weekly Sync",
            startedAt: Date(timeIntervalSince1970: 1_715_324_400),
            endedAt: Date(timeIntervalSince1970: 1_715_328_300),
            status: .completed,
            audioFilePath: "/tmp/audio.wav",
            duration: 3_900
        )
        let transcript = StoredTranscript(
            speakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Alice"),
                TranscriptSpeaker(id: "speaker-2", displayName: "Bob")
            ],
            segments: [
                TranscriptSegment(text: "Kickoff update.", startTime: 0, endTime: 2, speakerID: "speaker-1"),
                TranscriptSegment(text: "Next agenda point.", startTime: 2, endTime: 4, speakerID: "speaker-1"),
                TranscriptSegment(text: "Looks good to me.", startTime: 4, endTime: 6, speakerID: "speaker-2")
            ]
        )

        let markdown = renderMeetingTranscriptExportMarkdown(
            meeting: meeting,
            transcript: transcript
        )
        let expectedDateText = transcriptExportDateText(for: meeting.startedAt)

        #expect(markdown == """
        # Weekly Sync

        Date: **\(expectedDateText)**

        Duration: **01:05**

        ## Alice
        Kickoff update.

        Next agenda point.

        ## Bob
        Looks good to me.
        """)
    }

    @Test
    func exportMarkdownUsesFallbacksForUntitledMeetingUnknownSpeakerAndMissingDuration() {
        let meeting = Meeting(
            title: "   ",
            startedAt: Date(timeIntervalSince1970: 1_715_328_000),
            status: .completed,
            audioFilePath: "/tmp/audio.wav"
        )
        let transcript = StoredTranscript(
            speakers: [],
            segments: [
                TranscriptSegment(text: "  Hello there.  ", startTime: 0, endTime: 1, speakerID: nil),
                TranscriptSegment(text: "   ", startTime: 1, endTime: 2, speakerID: nil)
            ]
        )

        let markdown = renderMeetingTranscriptExportMarkdown(
            meeting: meeting,
            transcript: transcript
        )
        let expectedDateText = transcriptExportDateText(for: meeting.startedAt)

        #expect(markdown == """
        # Untitled Meeting

        Date: **\(expectedDateText)**

        Duration: **00:00**

        ## Speaker
        Hello there.
        """)
    }

    @Test
    func exportMarkdownBodyOmitsMeetingHeadersAndKeepsGroupedSpeakerSections() {
        let meeting = Meeting(
            title: "Weekly Sync",
            startedAt: Date(timeIntervalSince1970: 1_715_324_400),
            status: .completed,
            audioFilePath: "/tmp/audio.wav",
            duration: 3_900
        )
        let transcript = StoredTranscript(
            speakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Alice"),
                TranscriptSpeaker(id: "speaker-2", displayName: "Bob")
            ],
            segments: [
                TranscriptSegment(text: "Kickoff update.", startTime: 0, endTime: 2, speakerID: "speaker-1"),
                TranscriptSegment(text: "Next agenda point.", startTime: 2, endTime: 4, speakerID: "speaker-1"),
                TranscriptSegment(text: "Looks good to me.", startTime: 4, endTime: 6, speakerID: "speaker-2")
            ]
        )

        let markdown = renderMeetingTranscriptExportMarkdownBody(
            meeting: meeting,
            transcript: transcript
        )

        #expect(markdown == """
        ## Alice
        Kickoff update.

        Next agenda point.

        ## Bob
        Looks good to me.
        """)
    }

    @Test
    func exportDurationRoundsDownToWholeMinutes() {
        #expect(transcriptExportDurationText(59) == "00:00")
        #expect(transcriptExportDurationText(60) == "00:01")
        #expect(transcriptExportDurationText(3_661) == "01:01")
    }
}
