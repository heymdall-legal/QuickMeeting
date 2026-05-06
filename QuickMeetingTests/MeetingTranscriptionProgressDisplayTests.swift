import Foundation
import Testing
@testable import QuickMeeting

struct MeetingTranscriptionProgressDisplayTests {
    @Test
    func progressTextRoundsDownToWholePercent() {
        #expect(transcriptionProgressText(0.428) == "42% complete")
    }

    @Test
    func transcribingMeetingUsesProgressPane() {
        let state = transcriptPaneState(
            meetingStatus: .transcribing,
            transcriptFilePath: nil,
            progress: 0.42
        )

        #expect(state == .transcribing(progress: 0.42))
    }

    @Test
    func completedMeetingKeepsTranscriptPaneEvenWithoutProgress() {
        let state = transcriptPaneState(
            meetingStatus: .completed,
            transcriptFilePath: "/tmp/transcript.txt",
            progress: nil
        )

        #expect(state == .transcriptFile("/tmp/transcript.txt"))
    }
}
