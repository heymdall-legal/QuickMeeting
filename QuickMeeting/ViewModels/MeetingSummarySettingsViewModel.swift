import Combine
import Foundation

@MainActor
final class MeetingSummarySettingsViewModel: ObservableObject {
    static let defaultPromptTemplate = """
    Summarize the following meeting transcript from {date}.

    Return:
    • A 2–3 sentence overview
    • Key decisions
    • Action items (owner — task)

    Transcript:
    {text}
    """

    @Published var baseURL: String
    @Published var authToken: String
    @Published var modelName: String
    @Published var promptTemplate: String

    private let settingsStore: any MeetingSummarySettingsStoring

    init(settingsStore: (any MeetingSummarySettingsStoring)? = nil) {
        let settingsStore = settingsStore ?? MeetingSummarySettingsStore()
        self.settingsStore = settingsStore
        let settings = settingsStore.settings()
        baseURL = settings.baseURL ?? ""
        authToken = settings.authToken ?? ""
        modelName = settings.modelName ?? ""
        promptTemplate = settings.promptTemplate ?? Self.defaultPromptTemplate
    }

    func save() {
        settingsStore.saveSettings(
            .init(
                baseURL: baseURL,
                authToken: authToken,
                modelName: modelName,
                promptTemplate: promptTemplate
            )
        )
    }
}
