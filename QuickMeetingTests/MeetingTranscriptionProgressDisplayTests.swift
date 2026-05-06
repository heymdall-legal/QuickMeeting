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
            progress: 0.42,
            diarizationProgress: nil
        )

        #expect(state == .transcribing(progress: 0.42))
    }

    @Test
    func completedMeetingKeepsTranscriptPaneEvenWithoutProgress() {
        let state = transcriptPaneState(
            meetingStatus: .completed,
            transcriptFilePath: "/tmp/transcript.txt",
            progress: nil,
            diarizationProgress: nil
        )

        #expect(state == .transcriptFile("/tmp/transcript.txt"))
    }

    @Test
    func diarizingMeetingUsesDiarizingPane() {
        let state = transcriptPaneState(
            meetingStatus: .transcribing,
            transcriptFilePath: nil,
            progress: nil,
            diarizationProgress: 0.6
        )

        #expect(state == .diarizing(progress: 0.6))
    }

    @Test
    func diarizationTakesPrecedenceOverTranscriptionProgress() {
        let state = transcriptPaneState(
            meetingStatus: .transcribing,
            transcriptFilePath: nil,
            progress: 1.0,
            diarizationProgress: 0.3
        )

        #expect(state == .diarizing(progress: 0.3))
    }
}
