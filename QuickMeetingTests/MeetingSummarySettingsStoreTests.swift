import Foundation
import Testing
@testable import QuickMeeting

struct MeetingSummarySettingsStoreTests {
    @Test
    func returnsNilValidatedSettingsWhenAnyRequiredValueIsMissing() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = MeetingSummarySettingsStore(userDefaults: defaults)

        #expect(store.settings() == MeetingSummarySettings(
            baseURL: nil,
            authToken: nil,
            authHeaderName: nil,
            modelName: nil,
            promptTemplate: nil,
            correctionModelName: nil,
            correctionPromptTemplate: nil
        ))
        #expect(store.validatedSettings() == nil)
        #expect(store.validatedCorrectionSettings() == nil)
    }

    @Test
    func persistsAndReloadsAllRawValues() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = MeetingSummarySettingsStore(userDefaults: defaults)

        store.saveSettings(.init(
            baseURL: " https://example.com ",
            authToken: " token ",
            authHeaderName: " x-auth-token ",
            modelName: " gpt-4o-mini ",
            promptTemplate: "Summarize {text} for {date}",
            correctionModelName: " gpt-4.1-mini ",
            correctionPromptTemplate: "Correct {text} using {glossary}"
        ))

        #expect(store.settings() == MeetingSummarySettings(
            baseURL: " https://example.com ",
            authToken: " token ",
            authHeaderName: " x-auth-token ",
            modelName: " gpt-4o-mini ",
            promptTemplate: "Summarize {text} for {date}",
            correctionModelName: " gpt-4.1-mini ",
            correctionPromptTemplate: "Correct {text} using {glossary}"
        ))
    }

    @Test
    func validatedSettingsTrimWhitespaceAndRequireAllValues() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = MeetingSummarySettingsStore(userDefaults: defaults)
        store.saveSettings(.init(
            baseURL: " https://example.com/v1 ",
            authToken: " secret-token ",
            authHeaderName: " x-api-key ",
            modelName: " gpt-4o-mini ",
            promptTemplate: " Summarize {text} on {date} ",
            correctionModelName: " gpt-4.1-mini ",
            correctionPromptTemplate: " Correct {text} "
        ))

        #expect(store.validatedSettings() == ValidatedMeetingSummarySettings(
            baseURL: "https://example.com/v1",
            authToken: "secret-token",
            authHeaderName: "x-api-key",
            modelName: "gpt-4o-mini",
            promptTemplate: "Summarize {text} on {date}"
        ))
        #expect(store.validatedCorrectionSettings() == ValidatedLLMCorrectionSettings(
            baseURL: "https://example.com/v1",
            authToken: "secret-token",
            authHeaderName: "x-api-key",
            modelName: "gpt-4.1-mini",
            promptTemplate: "Correct {text}"
        ))
    }

    @Test
    func validatedSettingsDefaultAuthHeaderNameToAuthorization() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = MeetingSummarySettingsStore(userDefaults: defaults)
        store.saveSettings(.init(
            baseURL: "https://example.com/v1",
            authToken: "secret-token",
            authHeaderName: nil,
            modelName: "gpt-4o-mini",
            promptTemplate: "Summarize {text}",
            correctionModelName: "gpt-4.1-mini",
            correctionPromptTemplate: "Correct {text}"
        ))

        #expect(store.validatedSettings()?.authHeaderName == "Authorization")
        #expect(store.validatedCorrectionSettings()?.authHeaderName == "Authorization")
    }
}
