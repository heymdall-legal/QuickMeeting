//
//  TranscriptionSettingsViewModel.swift
//  QuickMeeting
//
//  Backs the default-language control in the Settings sheet.
//

import Combine
import Foundation

@MainActor
final class TranscriptionSettingsViewModel: ObservableObject {
    @Published private(set) var languageCode: String?
    @Published private(set) var ctcMode: TranscriptionCTCMode
    @Published private(set) var isLLMCorrectionEnabled: Bool
    @Published private(set) var offlineDiarization: OfflineDiarizationConfiguration
    @Published private(set) var voiceBankMatching: VoiceBankMatchingConfiguration
    @Published private(set) var glossaryTerms: [TranscriptionGlossaryTerm]
    @Published private(set) var isGlossaryLoaded: Bool

    private let settingsStore: any TranscriptionLanguageStoring
    private let glossaryStore: TranscriptionGlossaryStore

    init(
        settingsStore: any TranscriptionLanguageStoring,
        glossaryStore: TranscriptionGlossaryStore = TranscriptionGlossaryStore()
    ) {
        self.settingsStore = settingsStore
        self.glossaryStore = glossaryStore
        let options = settingsStore.pipelineOptions()
        languageCode = options.languageCode
        ctcMode = options.ctcMode
        isLLMCorrectionEnabled = options.isLLMCorrectionEnabled
        offlineDiarization = options.offlineDiarization
        voiceBankMatching = options.voiceBankMatching
        glossaryTerms = []
        isGlossaryLoaded = false
    }

    var options: [TranscriptionLanguageOption] { TranscriptionLanguageOption.all }
    var ctcOptions: [TranscriptionCTCMode] { TranscriptionCTCMode.allCases }
    var clusteringPresets: [OfflineClusteringPreset] { OfflineClusteringPreset.allCases }
    var diarizationStepRatios: [Double] { [0.15, 0.2, 0.25] }
    var embeddingSkipStrategies: [OfflineEmbeddingSkipStrategy] { OfflineEmbeddingSkipStrategy.allCases }
    var voiceBankMinimumScores: [Float] { [0.75, 0.8, 0.85, 0.9] }
    var voiceBankAmbiguityMargins: [Float] { [0.03, 0.05, 0.08, 0.1] }
    var voiceBankMinimumSpeechDurations: [TimeInterval] { [1, 2, 3, 5] }

    var selectedLanguageName: String { TranscriptionLanguageOption.name(for: languageCode) }
    var selectedClusteringName: String {
        offlineDiarization.clusteringPreset?.displayName
            ?? String(format: "Custom · %.2f", offlineDiarization.clusteringThreshold)
    }

    func selectLanguage(code: String?) {
        languageCode = code
        savePipelineOptions()
    }

    func selectCTCMode(_ mode: TranscriptionCTCMode) {
        ctcMode = mode
        savePipelineOptions()
    }

    func setLLMCorrectionEnabled(_ isEnabled: Bool) {
        isLLMCorrectionEnabled = isEnabled
        savePipelineOptions()
    }

    func selectClusteringPreset(_ preset: OfflineClusteringPreset) {
        offlineDiarization.clusteringThreshold = preset.threshold
        savePipelineOptions()
    }

    func selectDiarizationStepRatio(_ ratio: Double) {
        offlineDiarization.segmentationStepRatio = ratio
        savePipelineOptions()
    }

    func selectEmbeddingSkipStrategy(_ strategy: OfflineEmbeddingSkipStrategy) {
        offlineDiarization.embeddingSkipStrategy = strategy
        savePipelineOptions()
    }

    func selectVoiceBankMinimumScore(_ score: Float) {
        voiceBankMatching.minimumScore = score
        savePipelineOptions()
    }

    func selectVoiceBankAmbiguityMargin(_ margin: Float) {
        voiceBankMatching.ambiguityMargin = margin
        savePipelineOptions()
    }

    func selectVoiceBankMinimumSpeechDuration(_ duration: TimeInterval) {
        voiceBankMatching.minimumSpeechDurationSeconds = duration
        savePipelineOptions()
    }

    func loadGlossaryIfNeeded() {
        guard !isGlossaryLoaded else { return }
        glossaryTerms = glossaryStore.terms()
        isGlossaryLoaded = true
    }

    func addGlossaryTerm(text: String, aliases: [String] = []) {
        loadGlossaryIfNeeded()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        glossaryTerms.append(
            TranscriptionGlossaryTerm(
                text: trimmed,
                aliases: aliases,
                weight: 10,
                isEnabled: true,
                createdAt: now,
                updatedAt: now
            )
        )
        glossaryStore.saveTerms(glossaryTerms)
    }

    func removeGlossaryTerm(id: UUID) {
        loadGlossaryIfNeeded()
        glossaryTerms.removeAll { $0.id == id }
        glossaryStore.saveTerms(glossaryTerms)
    }

    func setGlossaryTermEnabled(id: UUID, isEnabled: Bool) {
        loadGlossaryIfNeeded()
        guard let index = glossaryTerms.firstIndex(where: { $0.id == id }) else { return }
        glossaryTerms[index].isEnabled = isEnabled
        glossaryTerms[index].updatedAt = Date()
        glossaryStore.saveTerms(glossaryTerms)
    }

    private func savePipelineOptions() {
        settingsStore.savePipelineOptions(
            TranscriptionPipelineOptions(
                languageCode: languageCode,
                ctcMode: ctcMode,
                isLLMCorrectionEnabled: isLLMCorrectionEnabled,
                offlineDiarization: offlineDiarization,
                voiceBankMatching: voiceBankMatching
            )
        )
    }
}
