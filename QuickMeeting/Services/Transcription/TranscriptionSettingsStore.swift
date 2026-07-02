//
//  TranscriptionSettingsStore.swift
//  QuickMeeting
//
//  Persists the default transcription language. A `nil` code means auto-detect.
//  Shared by the settings UI (writer) and the transcription service (reader).
//

import Foundation

protocol TranscriptionLanguageStoring {
    /// The persisted language code, or `nil` for auto-detect.
    func languageCode() -> String?
    func saveLanguageCode(_ code: String?)
    func pipelineOptions() -> TranscriptionPipelineOptions
    func savePipelineOptions(_ options: TranscriptionPipelineOptions)
}

nonisolated struct TranscriptionSettingsStore: TranscriptionLanguageStoring {
    private let userDefaults: UserDefaults
    private let languageCodeKey = "transcription.languageCode"
    private let ctcModeKey = "transcription.ctcMode"
    private let llmCorrectionEnabledKey = "transcription.llmCorrectionEnabled"

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

    func pipelineOptions() -> TranscriptionPipelineOptions {
        let mode = userDefaults.string(forKey: ctcModeKey)
            .flatMap(TranscriptionCTCMode.init(rawValue:)) ?? .off
        return TranscriptionPipelineOptions(
            languageCode: languageCode(),
            ctcMode: mode,
            isLLMCorrectionEnabled: userDefaults.bool(forKey: llmCorrectionEnabledKey)
        )
    }

    func savePipelineOptions(_ options: TranscriptionPipelineOptions) {
        saveLanguageCode(options.languageCode)
        userDefaults.set(options.ctcMode.rawValue, forKey: ctcModeKey)
        userDefaults.set(options.isLLMCorrectionEnabled, forKey: llmCorrectionEnabledKey)
    }
}

nonisolated struct TranscriptionGlossaryStore {
    private let userDefaults: UserDefaults
    private let termsKey = "transcription.glossaryTerms"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func terms() -> [TranscriptionGlossaryTerm] {
        guard let data = userDefaults.data(forKey: termsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([TranscriptionGlossaryTerm].self, from: data)) ?? []
    }

    func enabledTerms() -> [TranscriptionGlossaryTerm] {
        terms().filter { term in
            term.isEnabled && !term.normalizedText.isEmpty
        }
    }

    func saveTerms(_ terms: [TranscriptionGlossaryTerm]) {
        guard let data = try? JSONEncoder().encode(terms) else {
            return
        }
        userDefaults.set(data, forKey: termsKey)
    }
}
