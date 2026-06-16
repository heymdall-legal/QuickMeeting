import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct MeetingSummarySettingsViewModelTests {
    @Test
    func loadsStoredValuesIntoBindableFields() {
        let store = StubMeetingSummarySettingsViewModelStore()
        store.rawSettings = .init(
            baseURL: "https://example.com",
            authToken: "secret",
            authHeaderName: "x-api-key",
            modelName: "gpt-4o-mini",
            promptTemplate: "Summarize {text} on {date}"
        )

        let viewModel = MeetingSummarySettingsViewModel(settingsStore: store)

        #expect(viewModel.baseURL == "https://example.com")
        #expect(viewModel.authToken == "secret")
        #expect(viewModel.authHeaderName == "x-api-key")
        #expect(viewModel.modelName == "gpt-4o-mini")
        #expect(viewModel.promptTemplate == "Summarize {text} on {date}")
    }

    @Test
    func savePersistsEditedValues() {
        let store = StubMeetingSummarySettingsViewModelStore()
        let viewModel = MeetingSummarySettingsViewModel(settingsStore: store)
        viewModel.baseURL = "https://localhost:1234/v1"
        viewModel.authToken = "token"
        viewModel.authHeaderName = "x-auth-token"
        viewModel.modelName = "local-model"
        viewModel.promptTemplate = "Template {text}"

        viewModel.save()

        #expect(store.savedSettings == .init(
            baseURL: "https://localhost:1234/v1",
            authToken: "token",
            authHeaderName: "x-auth-token",
            modelName: "local-model",
            promptTemplate: "Template {text}"
        ))
    }
}

private final class StubMeetingSummarySettingsViewModelStore: MeetingSummarySettingsStoring, @unchecked Sendable {
    var rawSettings = MeetingSummarySettings(
        baseURL: nil,
        authToken: nil,
        authHeaderName: nil,
        modelName: nil,
        promptTemplate: nil
    )
    var savedSettings: MeetingSummarySettings?

    func settings() -> MeetingSummarySettings {
        rawSettings
    }

    func validatedSettings() -> ValidatedMeetingSummarySettings? {
        nil
    }

    func saveSettings(_ settings: MeetingSummarySettings) {
        savedSettings = settings
    }
}
