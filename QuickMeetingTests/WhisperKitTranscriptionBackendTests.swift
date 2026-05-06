import Combine
import Foundation
import Testing
@testable import QuickMeeting

struct WhisperKitTranscriptionBackendTests {
    @Test
    func observedProgressForwardsFractionCompletedUpdates() {
        let progress = Progress(totalUnitCount: 100)
        var reported = [Double]()

        let cancellable = observeTranscriptionProgress(progress) { value in
            reported.append(value)
        }

        progress.completedUnitCount = 25
        progress.completedUnitCount = 25
        progress.completedUnitCount = 70
        progress.completedUnitCount = 100
        cancellable.cancel()

        #expect(reported == [0.25, 0.7, 1.0])
    }

    @Test
    func cleanedTranscriptTextRemovesWhisperControlTokensAndTimestamps() {
        let rawText = "<|startoftranscript|><|ru|><|transcribe|><|0.00|> общались и поняли, что<|1.96|>"

        let cleanedText = cleanWhisperTranscriptText(rawText)

        #expect(cleanedText == "общались и поняли, что")
    }

    @Test
    func cleanedTranscriptTextPreservesNormalTranscriptContent() {
        let rawText = "Привет, команда.\nОбсудим план."

        let cleanedText = cleanWhisperTranscriptText(rawText)

        #expect(cleanedText == "Привет, команда.\nОбсудим план.")
    }
}
