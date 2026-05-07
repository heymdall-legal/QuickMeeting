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
            hasTranscript: false,
            progress: 0.42,
            diarizationProgress: nil
        )

        #expect(state == .transcribing(progress: 0.42))
    }

    @Test
    func completedMeetingKeepsTranscriptPaneEvenWithoutProgress() {
        let state = transcriptPaneState(
            meetingStatus: .completed,
            hasTranscript: true,
            progress: nil,
            diarizationProgress: nil
        )

        #expect(state == .transcript)
    }

    @Test
    func diarizingMeetingUsesDiarizingPane() {
        let state = transcriptPaneState(
            meetingStatus: .transcribing,
            hasTranscript: false,
            progress: nil,
            diarizationProgress: 0.6
        )

        #expect(state == .diarizing(progress: 0.6))
    }

    @Test
    func diarizationTakesPrecedenceOverTranscriptionProgress() {
        let state = transcriptPaneState(
            meetingStatus: .transcribing,
            hasTranscript: false,
            progress: 1.0,
            diarizationProgress: 0.3
        )

        #expect(state == .diarizing(progress: 0.3))
    }
}
