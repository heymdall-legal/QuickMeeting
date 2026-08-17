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
    private let diarizationClusteringThresholdKey = "transcription.diarization.clusteringThreshold"
    private let diarizationStepRatioKey = "transcription.diarization.stepRatio"
    private let diarizationEmbeddingSkipStrategyKey = "transcription.diarization.embeddingSkipStrategy"

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
        let storedThreshold = userDefaults.object(forKey: diarizationClusteringThresholdKey) as? Double
        let storedStepRatio = userDefaults.object(forKey: diarizationStepRatioKey) as? Double
        let storedSkipStrategy = userDefaults.string(forKey: diarizationEmbeddingSkipStrategyKey)
            .flatMap(OfflineEmbeddingSkipStrategy.init(rawValue:))
        return TranscriptionPipelineOptions(
            languageCode: languageCode(),
            ctcMode: mode,
            isLLMCorrectionEnabled: userDefaults.bool(forKey: llmCorrectionEnabledKey),
            offlineDiarization: OfflineDiarizationConfiguration(
                clusteringThreshold: storedThreshold ?? OfflineDiarizationConfiguration.legacy.clusteringThreshold,
                segmentationStepRatio: storedStepRatio ?? OfflineDiarizationConfiguration.legacy.segmentationStepRatio,
                embeddingSkipStrategy: storedSkipStrategy ?? OfflineDiarizationConfiguration.legacy.embeddingSkipStrategy
            )
        )
    }

    func savePipelineOptions(_ options: TranscriptionPipelineOptions) {
        saveLanguageCode(options.languageCode)
        userDefaults.set(options.ctcMode.rawValue, forKey: ctcModeKey)
        userDefaults.set(options.isLLMCorrectionEnabled, forKey: llmCorrectionEnabledKey)
        userDefaults.set(
            options.offlineDiarization.clusteringThreshold,
            forKey: diarizationClusteringThresholdKey
        )
        userDefaults.set(
            options.offlineDiarization.segmentationStepRatio,
            forKey: diarizationStepRatioKey
        )
        userDefaults.set(
            options.offlineDiarization.embeddingSkipStrategy.rawValue,
            forKey: diarizationEmbeddingSkipStrategyKey
        )
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
