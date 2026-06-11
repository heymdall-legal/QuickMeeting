import Foundation
import Testing
@testable import QuickMeeting

struct MeetingTranscriptionProgressDisplayTests {
    @Test
    func progressTextRoundsDownToWholePercent() {
        #expect(transcriptionProgressText(0.428) == "42% complete")
    }

    @Test
    func activeTranscriptionProgressUsesProgressPane() {
        let state = transcriptPaneState(
            hasTranscript: false,
            progress: 0.42,
            diarizationProgress: nil
        )

        #expect(state == .transcribing(progress: 0.42))
    }

    @Test
    func completedMeetingKeepsTranscriptPaneWhenNoProgressIsActive() {
        let state = transcriptPaneState(
            hasTranscript: true,
            progress: nil,
            diarizationProgress: nil
        )

        #expect(state == .transcript)
    }

    @Test
    func activeDiarizationProgressUsesDiarizingPane() {
        let state = transcriptPaneState(
            hasTranscript: false,
            progress: nil,
            diarizationProgress: 0.6
        )

        #expect(state == .diarizing(progress: 0.6))
    }

    @Test
    func diarizationTakesPrecedenceOverTranscriptionProgress() {
        let state = transcriptPaneState(
            hasTranscript: false,
            progress: 1.0,
            diarizationProgress: 0.3
        )

        #expect(state == .diarizing(progress: 0.3))
    }
}
