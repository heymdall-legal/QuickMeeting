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

    static let defaultCorrectionPromptTemplate = """
    Correct this meeting transcript.

    Rules:
    - Fix only ASR mistakes, punctuation, capitalization, and obvious glossary term spelling.
    - Do not change the meaning.
    - Do not add facts, action items, speakers, or details.
    - Preserve each segment id and return JSON: {"segments":[{"id":"...","text":"..."}]}.

    Glossary:
    {glossary}

    Transcript segments:
    {text}
    """

    @Published var baseURL: String
    @Published var authToken: String
    @Published var authHeaderName: String
    @Published var modelName: String
    @Published var promptTemplate: String
    @Published var correctionModelName: String
    @Published var correctionPromptTemplate: String

    private let settingsStore: any MeetingSummarySettingsStoring

    init(settingsStore: (any MeetingSummarySettingsStoring)? = nil) {
        let settingsStore = settingsStore ?? MeetingSummarySettingsStore()
        self.settingsStore = settingsStore
        let settings = settingsStore.settings()
        baseURL = settings.baseURL ?? ""
        authToken = settings.authToken ?? ""
        authHeaderName = settings.authHeaderName ?? "Authorization"
        modelName = settings.modelName ?? ""
        promptTemplate = settings.promptTemplate ?? Self.defaultPromptTemplate
        correctionModelName = settings.correctionModelName ?? ""
        correctionPromptTemplate = settings.correctionPromptTemplate ?? Self.defaultCorrectionPromptTemplate
    }

    func save() {
        settingsStore.saveSettings(
            .init(
                baseURL: baseURL,
                authToken: authToken,
                authHeaderName: authHeaderName,
                modelName: modelName,
                promptTemplate: promptTemplate,
                correctionModelName: correctionModelName,
                correctionPromptTemplate: correctionPromptTemplate
            )
        )
    }
}
