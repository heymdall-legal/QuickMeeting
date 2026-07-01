import Foundation
import Testing
@testable import QuickMeeting

struct TranscriptionSettingsStoreTests {
    @Test
    func pipelineOptionsDefaultToStableCurrentPath() {
        let defaults = makeDefaults()
        let store = TranscriptionSettingsStore(userDefaults: defaults)

        #expect(store.pipelineOptions() == TranscriptionPipelineOptions(
            languageCode: nil,
            ctcMode: .off,
            isLLMCorrectionEnabled: false,
            isRealtimeTranscriptionEnabled: false,
            realtimeTranscriptionBackend: .fluidAudio,
            realtimeTranscriptionEndpointURLString: "http://127.0.0.1:1234/v1/audio/transcriptions",
            realtimeTranscriptionModelName: "gigaam"
        ))
    }

    @Test
    func pipelineOptionsRoundTrip() {
        let defaults = makeDefaults()
        let store = TranscriptionSettingsStore(userDefaults: defaults)

        store.saveLanguageCode("de")
        store.savePipelineOptions(.init(
            languageCode: "fr",
            ctcMode: .ctc06b,
            isLLMCorrectionEnabled: true,
            isRealtimeTranscriptionEnabled: true,
            realtimeTranscriptionBackend: .customOpenAICompatible,
            realtimeTranscriptionEndpointURLString: "http://127.0.0.1:9000/v1/audio/transcriptions",
            realtimeTranscriptionModelName: "custom-ru"
        ))

        #expect(store.languageCode() == "fr")
        #expect(store.pipelineOptions() == TranscriptionPipelineOptions(
            languageCode: "fr",
            ctcMode: .ctc06b,
            isLLMCorrectionEnabled: true,
            isRealtimeTranscriptionEnabled: true,
            realtimeTranscriptionBackend: .customOpenAICompatible,
            realtimeTranscriptionEndpointURLString: "http://127.0.0.1:9000/v1/audio/transcriptions",
            realtimeTranscriptionModelName: "custom-ru"
        ))
    }

    @Test
    func glossaryTermsRoundTripAndEnabledTermsFilterEmptyDisabledEntries() {
        let defaults = makeDefaults()
        let store = TranscriptionGlossaryStore(userDefaults: defaults)
        let keptID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let disabledID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let emptyID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

        store.saveTerms([
            TranscriptionGlossaryTerm(
                id: keptID,
                text: "Core ML",
                aliases: ["CoreML", "core em el"],
                weight: 8,
                isEnabled: true,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20)
            ),
            TranscriptionGlossaryTerm(
                id: disabledID,
                text: "Parakeet",
                aliases: [],
                weight: nil,
                isEnabled: false,
                createdAt: Date(timeIntervalSince1970: 30),
                updatedAt: Date(timeIntervalSince1970: 40)
            ),
            TranscriptionGlossaryTerm(
                id: emptyID,
                text: "   ",
                aliases: ["   "],
                weight: nil,
                isEnabled: true,
                createdAt: Date(timeIntervalSince1970: 50),
                updatedAt: Date(timeIntervalSince1970: 60)
            ),
        ])

        #expect(store.terms().map(\.id) == [keptID, disabledID, emptyID])
        #expect(store.enabledTerms() == [
            TranscriptionGlossaryTerm(
                id: keptID,
                text: "Core ML",
                aliases: ["CoreML", "core em el"],
                weight: 8,
                isEnabled: true,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        ])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TranscriptionSettingsStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
