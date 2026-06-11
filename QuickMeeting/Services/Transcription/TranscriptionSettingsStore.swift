import Foundation

enum TranscriptionLanguage: String, CaseIterable, Equatable, Sendable {
    case none
    case russian
    case english

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .russian:
            return "Russian"
        case .english:
            return "English"
        }
    }

    var sidecarArgumentValue: String? {
        switch self {
        case .none:
            return nil
        case .russian:
            return "ru"
        case .english:
            return "en"
        }
    }
}

struct TranscriptionSettings: Equatable, Sendable {
    var language: TranscriptionLanguage
    var initialPrompt: String

    static let `default` = TranscriptionSettings(
        language: .none,
        initialPrompt: ""
    )
}

protocol TranscriptionSettingsStoring: Sendable {
    func load() -> TranscriptionSettings
    func save(_ settings: TranscriptionSettings)
}

struct TranscriptionSettingsStore: TranscriptionSettingsStoring {
    private let userDefaults: UserDefaults
    private let languageKey = "transcription.language"
    private let initialPromptKey = "transcription.initialPrompt"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> TranscriptionSettings {
        let language = userDefaults.string(forKey: languageKey)
            .flatMap(TranscriptionLanguage.init(rawValue:))
            ?? TranscriptionSettings.default.language
        let initialPrompt = userDefaults.string(forKey: initialPromptKey)
            ?? TranscriptionSettings.default.initialPrompt
        return TranscriptionSettings(
            language: language,
            initialPrompt: initialPrompt
        )
    }

    func save(_ settings: TranscriptionSettings) {
        userDefaults.set(settings.language.rawValue, forKey: languageKey)
        userDefaults.set(settings.initialPrompt, forKey: initialPromptKey)
    }
}
