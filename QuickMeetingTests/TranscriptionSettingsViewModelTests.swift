import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct TranscriptionSettingsViewModelTests {
    @Test
    func microphoneSpeakerNameDefaultsToPlaceholderAndPersistsCustomName() {
        let defaults = makeDefaults()
        let settingsStore = TranscriptionSettingsStore(userDefaults: defaults)
        let viewModel = TranscriptionSettingsViewModel(settingsStore: settingsStore)

        #expect(viewModel.microphoneSpeakerDisplayName == "Microphone Owner")

        viewModel.setMicrophoneSpeakerDisplayName("  Maria Petrova  ")

        #expect(viewModel.microphoneSpeakerDisplayName == "  Maria Petrova  ")
        #expect(settingsStore.microphoneSpeakerDisplayName() == "Maria Petrova")
    }

    @Test
    func clearingMicrophoneSpeakerNameRestoresPlaceholder() {
        let defaults = makeDefaults()
        let settingsStore = TranscriptionSettingsStore(userDefaults: defaults)
        settingsStore.saveMicrophoneSpeakerDisplayName("Maria Petrova")
        let viewModel = TranscriptionSettingsViewModel(settingsStore: settingsStore)

        viewModel.setMicrophoneSpeakerDisplayName("   ")

        #expect(settingsStore.microphoneSpeakerDisplayName() == "Microphone Owner")
    }

    @Test
    func savesPipelineOptionsWhenControlsChange() {
        let defaults = makeDefaults()
        let settingsStore = TranscriptionSettingsStore(userDefaults: defaults)
        let glossaryStore = TranscriptionGlossaryStore(userDefaults: defaults)
        let viewModel = TranscriptionSettingsViewModel(
            settingsStore: settingsStore,
            glossaryStore: glossaryStore
        )

        viewModel.selectOfflineJobSchedule(.concurrent)
        viewModel.selectCTCMode(.ctc110m)
        viewModel.setLLMCorrectionEnabled(true)
        viewModel.selectClusteringPreset(.upstream06)
        viewModel.selectDiarizationStepRatio(0.15)
        viewModel.selectEmbeddingSkipStrategy(.maskSimilarity095)
        viewModel.selectVoiceBankMinimumScore(0.85)
        viewModel.selectVoiceBankAmbiguityMargin(0.08)
        viewModel.selectVoiceBankMinimumSpeechDuration(3)

        #expect(settingsStore.pipelineOptions() == TranscriptionPipelineOptions(
            offlineASRModelID: .parakeetTDTv3,
            offlineJobSchedule: .concurrent,
            languageCode: "ru-RU",
            ctcMode: .ctc110m,
            isLLMCorrectionEnabled: true,
            offlineDiarization: OfflineDiarizationConfiguration(
                clusteringThreshold: 0.6,
                segmentationStepRatio: 0.15,
                embeddingSkipStrategy: .maskSimilarity095
            ),
            voiceBankMatching: VoiceBankMatchingConfiguration(
                minimumScore: 0.85,
                ambiguityMargin: 0.08,
                minimumSpeechDurationSeconds: 3
            )
        ))
    }

    @Test
    func addGlossaryTermPersistsTrimmedEnabledTerm() {
        let defaults = makeDefaults()
        let viewModel = TranscriptionSettingsViewModel(
            settingsStore: TranscriptionSettingsStore(userDefaults: defaults),
            glossaryStore: TranscriptionGlossaryStore(userDefaults: defaults)
        )

        viewModel.addGlossaryTerm(text: "  Kubernetes  ")
        viewModel.addGlossaryTerm(text: "   ")

        #expect(viewModel.glossaryTerms.map(\.text) == ["Kubernetes"])
        #expect(TranscriptionGlossaryStore(userDefaults: defaults).enabledTerms().map(\.text) == ["Kubernetes"])
    }

    @Test
    func glossaryTermsAreLoadedLazilyForSettingsUI() {
        let defaults = makeDefaults()
        let glossaryStore = TranscriptionGlossaryStore(userDefaults: defaults)
        glossaryStore.saveTerms([TranscriptionGlossaryTerm(text: "Kubernetes")])
        let viewModel = TranscriptionSettingsViewModel(
            settingsStore: TranscriptionSettingsStore(userDefaults: defaults),
            glossaryStore: glossaryStore
        )

        #expect(viewModel.isGlossaryLoaded == false)
        #expect(viewModel.glossaryTerms.isEmpty)

        viewModel.loadGlossaryIfNeeded()

        #expect(viewModel.isGlossaryLoaded)
        #expect(viewModel.glossaryTerms.map(\.text) == ["Kubernetes"])
    }

    @Test
    func addingGlossaryTermBeforeUILoadPreservesPersistedTerms() {
        let defaults = makeDefaults()
        let glossaryStore = TranscriptionGlossaryStore(userDefaults: defaults)
        glossaryStore.saveTerms([TranscriptionGlossaryTerm(text: "Kubernetes")])
        let viewModel = TranscriptionSettingsViewModel(
            settingsStore: TranscriptionSettingsStore(userDefaults: defaults),
            glossaryStore: glossaryStore
        )

        viewModel.addGlossaryTerm(text: "Core ML")

        #expect(viewModel.isGlossaryLoaded)
        #expect(viewModel.glossaryTerms.map(\.text) == ["Kubernetes", "Core ML"])
        #expect(glossaryStore.terms().map(\.text) == ["Kubernetes", "Core ML"])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TranscriptionSettingsViewModelTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
