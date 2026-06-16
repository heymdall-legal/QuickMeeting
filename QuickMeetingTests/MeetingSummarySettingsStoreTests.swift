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
            promptTemplate: nil
        ))
        #expect(store.validatedSettings() == nil)
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
            promptTemplate: "Summarize {text} for {date}"
        ))

        #expect(store.settings() == MeetingSummarySettings(
            baseURL: " https://example.com ",
            authToken: " token ",
            authHeaderName: " x-auth-token ",
            modelName: " gpt-4o-mini ",
            promptTemplate: "Summarize {text} for {date}"
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
            promptTemplate: " Summarize {text} on {date} "
        ))

        #expect(store.validatedSettings() == ValidatedMeetingSummarySettings(
            baseURL: "https://example.com/v1",
            authToken: "secret-token",
            authHeaderName: "x-api-key",
            modelName: "gpt-4o-mini",
            promptTemplate: "Summarize {text} on {date}"
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
            promptTemplate: "Summarize {text}"
        ))

        #expect(store.validatedSettings()?.authHeaderName == "Authorization")
    }
}
