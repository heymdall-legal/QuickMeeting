import Foundation

struct MeetingSummarySettings: Equatable {
    var baseURL: String?
    var authToken: String?
    var authHeaderName: String?
    var modelName: String?
    var promptTemplate: String?
}

struct ValidatedMeetingSummarySettings: Equatable, Sendable {
    let baseURL: String
    let authToken: String
    let authHeaderName: String
    let modelName: String
    let promptTemplate: String
}

protocol MeetingSummarySettingsStoring: Sendable {
    func settings() -> MeetingSummarySettings
    func validatedSettings() -> ValidatedMeetingSummarySettings?
    func saveSettings(_ settings: MeetingSummarySettings)
}

struct MeetingSummarySettingsStore: MeetingSummarySettingsStoring {
    private let userDefaults: UserDefaults
    private static let defaultAuthHeaderName = "Authorization"
    private let baseURLKey = "meetingSummary.baseURL"
    private let authTokenKey = "meetingSummary.authToken"
    private let authHeaderNameKey = "meetingSummary.authHeaderName"
    private let modelNameKey = "meetingSummary.modelName"
    private let promptTemplateKey = "meetingSummary.promptTemplate"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func settings() -> MeetingSummarySettings {
        MeetingSummarySettings(
            baseURL: userDefaults.string(forKey: baseURLKey),
            authToken: userDefaults.string(forKey: authTokenKey),
            authHeaderName: userDefaults.string(forKey: authHeaderNameKey),
            modelName: userDefaults.string(forKey: modelNameKey),
            promptTemplate: userDefaults.string(forKey: promptTemplateKey)
        )
    }

    func validatedSettings() -> ValidatedMeetingSummarySettings? {
        let current = settings()

        guard
            let baseURL = current.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            let authToken = current.authToken?.trimmingCharacters(in: .whitespacesAndNewlines),
            let modelName = current.modelName?.trimmingCharacters(in: .whitespacesAndNewlines),
            let promptTemplate = current.promptTemplate?.trimmingCharacters(in: .whitespacesAndNewlines),
            !baseURL.isEmpty,
            !authToken.isEmpty,
            !modelName.isEmpty,
            !promptTemplate.isEmpty
        else {
            return nil
        }
        let trimmedAuthHeaderName = current.authHeaderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let authHeaderName: String
        if let trimmedAuthHeaderName, !trimmedAuthHeaderName.isEmpty {
            authHeaderName = trimmedAuthHeaderName
        } else {
            authHeaderName = Self.defaultAuthHeaderName
        }

        return ValidatedMeetingSummarySettings(
            baseURL: baseURL,
            authToken: authToken,
            authHeaderName: authHeaderName,
            modelName: modelName,
            promptTemplate: promptTemplate
        )
    }

    func saveSettings(_ settings: MeetingSummarySettings) {
        save(settings.baseURL, forKey: baseURLKey)
        save(settings.authToken, forKey: authTokenKey)
        save(settings.authHeaderName, forKey: authHeaderNameKey)
        save(settings.modelName, forKey: modelNameKey)
        save(settings.promptTemplate, forKey: promptTemplateKey)
    }

    private func save(_ value: String?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}
