import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct TranscriptionSettingsViewModelTests {
    @Test
    func loadExposesPersistedSettings() async {
        let store = InMemoryTranscriptionSettingsStore(
            settings: TranscriptionSettings(
                language: .english,
                initialPrompt: "Alice, revenue recognition"
            )
        )
        let viewModel = TranscriptionSettingsViewModel(settingsStore: store)

        await viewModel.load()

        #expect(viewModel.language == .english)
        #expect(viewModel.initialPrompt == "Alice, revenue recognition")
    }

    @Test
    func savePersistsCurrentSettings() async {
        let store = InMemoryTranscriptionSettingsStore(settings: .default)
        let viewModel = TranscriptionSettingsViewModel(settingsStore: store)
        viewModel.language = .russian
        viewModel.initialPrompt = "Dmitry, quarterly roadmap"

        await viewModel.save()

        #expect(store.settings == TranscriptionSettings(
            language: .russian,
            initialPrompt: "Dmitry, quarterly roadmap"
        ))
    }
}

private final class InMemoryTranscriptionSettingsStore: TranscriptionSettingsStoring, @unchecked Sendable {
    var settings: TranscriptionSettings

    init(settings: TranscriptionSettings) {
        self.settings = settings
    }

    func load() -> TranscriptionSettings {
        settings
    }

    func save(_ settings: TranscriptionSettings) {
        self.settings = settings
    }
}
