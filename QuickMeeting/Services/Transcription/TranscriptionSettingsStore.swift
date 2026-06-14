//
//  TranscriptionSettingsStore.swift
//  QuickMeeting
//
//  Persists the default transcription language. A `nil` code means auto-detect.
//  Shared by the settings UI (writer) and the transcription service (reader).
//

import Foundation

protocol TranscriptionLanguageStoring: Sendable {
    /// The persisted language code, or `nil` for auto-detect.
    func languageCode() -> String?
    func saveLanguageCode(_ code: String?)
}

struct TranscriptionSettingsStore: TranscriptionLanguageStoring {
    private let userDefaults: UserDefaults
    private let languageCodeKey = "transcription.languageCode"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func languageCode() -> String? {
        userDefaults.string(forKey: languageCodeKey)
    }

    func saveLanguageCode(_ code: String?) {
        if let code {
            userDefaults.set(code, forKey: languageCodeKey)
        } else {
            userDefaults.removeObject(forKey: languageCodeKey)
        }
    }
}
