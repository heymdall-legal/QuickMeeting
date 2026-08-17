import FluidAudio
import Foundation
import Testing
@testable import QuickMeeting

struct ASRBackendTests {
    @Test
    func selectorContainsOnlySmokeTestedBackendAndTracksCurrentGigaAMVariants() {
        #expect(OfflineASRModelCatalog.selectable.map(\.id) == [.parakeetTDTv3])
        #expect(GigaAMMultilingualVariant.allCases.map(\.rawValue) == [
            "multilingual_ssl",
            "multilingual_large_ssl",
            "multilingual_ctc",
            "multilingual_large_ctc",
        ])
    }

    @Test
    func russianV3SelectionUsesExplicitLanguageAndMultilingualLongFormConfig() {
        let selection = ParakeetLongFormConfiguration(languageCode: "ru", modelVersion: .v3)

        #expect(selection.language?.rawValue == "ru")
        #expect(selection.asrConfig.melChunkContext == false)
        #expect(selection.asrConfig.seamGapRepair == true)
    }

    @Test
    func autoAndUnknownLanguageCodesDoNotForceAFluidLanguage() {
        #expect(ParakeetLongFormConfiguration(languageCode: nil, modelVersion: .v3).language == nil)
        #expect(ParakeetLongFormConfiguration(languageCode: "unsupported", modelVersion: .v3).language == nil)
    }

    @Test
    func fluidResultConvertsSubwordsToBackendNeutralTimedWords() throws {
        let result = ASRResult(
            text: "Привет мир",
            confidence: 0.9,
            duration: 1.5,
            processingTime: 0.4,
            tokenTimings: [
                token(" При", start: 0.1, end: 0.2, confidence: 0.95),
                token("вет", start: 0.2, end: 0.45, confidence: 0.8),
                token("▁мир", start: 0.6, end: 0.9, confidence: 0.9),
            ]
        )

        let transcript = ParakeetASRBackend.makeTimedTranscript(from: result)

        #expect(transcript.text == "Привет мир")
        #expect(transcript.words == [
            TimedWord(text: "Привет", startTime: 0.1, endTime: 0.45, confidence: 0.8),
            TimedWord(text: "мир", startTime: 0.6, endTime: 0.9, confidence: 0.9),
        ])
    }

    private func token(
        _ text: String,
        start: TimeInterval,
        end: TimeInterval,
        confidence: Float
    ) -> TokenTiming {
        TokenTiming(
            token: text,
            tokenId: 1,
            startTime: start,
            endTime: end,
            confidence: confidence
        )
    }
}
