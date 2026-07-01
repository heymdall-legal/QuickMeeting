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
    private let realtimeTranscriptionEnabledKey = "transcription.realtimeTranscriptionEnabled"
    private let realtimeTranscriptionBackendKey = "transcription.realtimeTranscriptionBackend"
    private let realtimeTranscriptionEndpointURLStringKey = "transcription.realtimeTranscriptionEndpointURLString"
    private let realtimeTranscriptionModelNameKey = "transcription.realtimeTranscriptionModelName"

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
            isLLMCorrectionEnabled: userDefaults.bool(forKey: llmCorrectionEnabledKey),
            isRealtimeTranscriptionEnabled: userDefaults.bool(forKey: realtimeTranscriptionEnabledKey),
            realtimeTranscriptionBackend: realtimeTranscriptionBackend(),
            realtimeTranscriptionEndpointURLString: userDefaults.string(
                forKey: realtimeTranscriptionEndpointURLStringKey
            ) ?? TranscriptionPipelineOptions.defaultRealtimeTranscriptionEndpointURLString,
            realtimeTranscriptionModelName: userDefaults.string(
                forKey: realtimeTranscriptionModelNameKey
            ) ?? TranscriptionPipelineOptions.defaultRealtimeTranscriptionModelName
        )
    }

    func savePipelineOptions(_ options: TranscriptionPipelineOptions) {
        saveLanguageCode(options.languageCode)
        userDefaults.set(options.ctcMode.rawValue, forKey: ctcModeKey)
        userDefaults.set(options.isLLMCorrectionEnabled, forKey: llmCorrectionEnabledKey)
        userDefaults.set(options.isRealtimeTranscriptionEnabled, forKey: realtimeTranscriptionEnabledKey)
        userDefaults.set(options.realtimeTranscriptionBackend.rawValue, forKey: realtimeTranscriptionBackendKey)
        userDefaults.set(
            options.realtimeTranscriptionEndpointURLString,
            forKey: realtimeTranscriptionEndpointURLStringKey
        )
        userDefaults.set(options.realtimeTranscriptionModelName, forKey: realtimeTranscriptionModelNameKey)
    }

    private func realtimeTranscriptionBackend() -> RealtimeTranscriptionBackend {
        userDefaults.string(forKey: realtimeTranscriptionBackendKey)
            .flatMap(RealtimeTranscriptionBackend.init(rawValue:)) ?? .fluidAudio
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
