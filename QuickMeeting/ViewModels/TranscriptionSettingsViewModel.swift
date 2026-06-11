import Combine
import Foundation

@MainActor
final class TranscriptionSettingsViewModel: ObservableObject {
    @Published var language: TranscriptionLanguage = .none
    @Published var initialPrompt = ""

    private let settingsStore: any TranscriptionSettingsStoring

    init(settingsStore: any TranscriptionSettingsStoring) {
        self.settingsStore = settingsStore
    }

    func load() async {
        let settings = settingsStore.load()
        language = settings.language
        initialPrompt = settings.initialPrompt
    }

    func save() async {
        settingsStore.save(
            TranscriptionSettings(
                language: language,
                initialPrompt: initialPrompt
            )
        )
    }
}
