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
            diarizationProgress: DiarizationProgressState(progress: 0.6, stepName: "embeddings")
        )

        #expect(state == .diarizing(DiarizationProgressState(progress: 0.6, stepName: "embeddings")))
    }

    @Test
    func diarizationTakesPrecedenceOverTranscriptionProgress() {
        let state = transcriptPaneState(
            hasTranscript: false,
            progress: 1.0,
            diarizationProgress: DiarizationProgressState(progress: 0.3, stepName: "diarization")
        )

        #expect(state == .diarizing(DiarizationProgressState(progress: 0.3, stepName: "diarization")))
    }

    @Test
    func diarizationTitleUsesCurrentStepNameWhenAvailable() {
        #expect(diarizationProgressTitle(stepName: "embeddings") == "Embeddings...")
    }

    @Test
    func diarizationTitleFallsBackWhenStepNameIsMissing() {
        #expect(diarizationProgressTitle(stepName: nil) == "Diarization...")
    }

    @Test
    func diarizationTitleHumanizesDelimitedStepNames() {
        #expect(diarizationProgressTitle(stepName: "speaker_embeddings") == "Speaker Embeddings...")
    }
}
