import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct TranscriptionSettingsViewModelTests {
    @Test
    func savesPipelineOptionsWhenControlsChange() {
        let defaults = makeDefaults()
        let settingsStore = TranscriptionSettingsStore(userDefaults: defaults)
        let glossaryStore = TranscriptionGlossaryStore(userDefaults: defaults)
        let viewModel = TranscriptionSettingsViewModel(
            settingsStore: settingsStore,
            glossaryStore: glossaryStore
        )

        viewModel.selectLanguage(code: "de")
        viewModel.selectCTCMode(.ctc110m)
        viewModel.setLLMCorrectionEnabled(true)
        viewModel.setRealtimeTranscriptionEnabled(true)

        #expect(settingsStore.pipelineOptions() == TranscriptionPipelineOptions(
            languageCode: "de",
            ctcMode: .ctc110m,
            isLLMCorrectionEnabled: true,
            isRealtimeTranscriptionEnabled: true
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
