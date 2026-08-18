import FluidAudio
import Foundation
import Testing
@testable import QuickMeeting

struct ASRBackendTests {
    @Test
    func selectorContainsAllOfflineBackendsWithRequestedExactVariants() {
        #expect(OfflineASRModelCatalog.selectable.map(\.id) == [
            .parakeetTDTv3,
            .qwen3ASR17B,
            .gigaAMV3,
        ])
        #expect(OfflineASRModelCatalog.descriptor(for: .qwen3ASR17B)?.exactVariant.contains("ForcedAligner") == true)
        #expect(OfflineASRModelCatalog.descriptor(for: .gigaAMV3)?.exactVariant.contains("e2e_rnnt") == true)
        #expect(NativeQwenASRBackend.snapshot.runtime.contains("MLX/Metal"))
        #expect(NativeGigaAMASRBackend.snapshot.modelVersion.contains("Q8_0"))
        #expect(NativeGigaAMASRBackend.snapshot.runtime.contains("transcribe.cpp"))
    }

    @Test
    func nativeChunkerSplitsNearSilenceWithoutDroppingSamples() {
        var samples = Array(repeating: Float(0.4), count: 48)
        samples.replaceSubrange(18..<24, with: repeatElement(Float.zero, count: 6))

        let chunks = NativeAudioChunker.chunks(
            samples: samples,
            sampleRate: 10,
            maximumDuration: 3,
            silenceSearchDuration: 1.5,
            minimumDuration: 1
        )

        #expect(chunks.count == 2)
        #expect(chunks.first?.range.upperBound == chunks.last?.range.lowerBound)
        #expect(chunks.first?.range.lowerBound == 0)
        #expect(chunks.last?.range.upperBound == samples.count)
        #expect(chunks.last?.startTime == Double(chunks.last?.range.lowerBound ?? 0) / 10)
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
