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
    @Published private(set) var microphoneSpeakerDisplayName: String
    @Published private(set) var offlineASRModelID: OfflineASRModelID
    @Published private(set) var offlineJobSchedule: OfflineJobSchedule
    @Published private(set) var languageCode: String?
    @Published private(set) var ctcMode: TranscriptionCTCMode
    @Published private(set) var isLLMCorrectionEnabled: Bool
    @Published private(set) var offlineDiarization: OfflineDiarizationConfiguration
    @Published private(set) var voiceBankMatching: VoiceBankMatchingConfiguration
    @Published private(set) var glossaryTerms: [TranscriptionGlossaryTerm]
    @Published private(set) var isGlossaryLoaded: Bool
    @Published private(set) var modelPreparationState: TranscriptionModelPreparationState
    @Published private(set) var onlineDraftModelState: OnlineDraftModelState

    private let settingsStore: any TranscriptionLanguageStoring
    private let glossaryStore: TranscriptionGlossaryStore
    private let modelPreparationCenter: TranscriptionModelPreparationCenter?
    private let onlineDraftCoordinator: OnlineDraftCoordinator?
    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: any TranscriptionLanguageStoring,
        glossaryStore: TranscriptionGlossaryStore = TranscriptionGlossaryStore(),
        modelPreparationCenter: TranscriptionModelPreparationCenter? = nil,
        onlineDraftCoordinator: OnlineDraftCoordinator? = nil
    ) {
        self.settingsStore = settingsStore
        self.glossaryStore = glossaryStore
        self.modelPreparationCenter = modelPreparationCenter
        self.onlineDraftCoordinator = onlineDraftCoordinator
        let options = settingsStore.pipelineOptions()
        microphoneSpeakerDisplayName = settingsStore.microphoneSpeakerDisplayName()
        offlineASRModelID = options.offlineASRModelID
        offlineJobSchedule = options.offlineJobSchedule
        languageCode = options.languageCode
        ctcMode = options.ctcMode
        isLLMCorrectionEnabled = options.isLLMCorrectionEnabled
        offlineDiarization = options.offlineDiarization
        voiceBankMatching = options.voiceBankMatching
        glossaryTerms = []
        isGlossaryLoaded = false
        modelPreparationState = modelPreparationCenter?.state(for: options.offlineASRModelID) ?? .notPrepared
        onlineDraftModelState = onlineDraftCoordinator?.modelState ?? .notPrepared

        modelPreparationCenter?.$stateByModel
            .sink { [weak self] states in
                guard let self else { return }
                self.modelPreparationState = states[self.offlineASRModelID] ?? .notPrepared
            }
            .store(in: &cancellables)

        onlineDraftCoordinator?.$modelState
            .sink { [weak self] state in
                self?.onlineDraftModelState = state
            }
            .store(in: &cancellables)
    }

    var options: [TranscriptionLanguageOption] { TranscriptionLanguageOption.all }
    var offlineASRModels: [OfflineASRModelDescriptor] { OfflineASRModelCatalog.selectable }
    var ctcOptions: [TranscriptionCTCMode] { TranscriptionCTCMode.allCases }
    var clusteringPresets: [OfflineClusteringPreset] { OfflineClusteringPreset.allCases }
    var diarizationStepRatios: [Double] { [0.15, 0.2, 0.25] }
    var embeddingSkipStrategies: [OfflineEmbeddingSkipStrategy] { OfflineEmbeddingSkipStrategy.allCases }
    var voiceBankMinimumScores: [Float] { [0.75, 0.8, 0.85, 0.9] }
    var voiceBankAmbiguityMargins: [Float] { [0.03, 0.05, 0.08, 0.1] }
    var voiceBankMinimumSpeechDurations: [TimeInterval] { [1, 2, 3, 5] }

    var selectedLanguageName: String { TranscriptionLanguageOption.name(for: languageCode) }
    var selectedOfflineASRModelName: String {
        OfflineASRModelCatalog.descriptor(for: offlineASRModelID)?.displayName ?? "Unavailable model"
    }
    var selectedClusteringName: String {
        offlineDiarization.clusteringPreset?.displayName
            ?? String(format: "Custom · %.2f", offlineDiarization.clusteringThreshold)
    }

    func setMicrophoneSpeakerDisplayName(_ displayName: String) {
        microphoneSpeakerDisplayName = displayName
        settingsStore.saveMicrophoneSpeakerDisplayName(displayName)
    }

    func selectLanguage(code: String?) {
        languageCode = "ru-RU"
        savePipelineOptions()
    }

    func selectOfflineASRModel(_ id: OfflineASRModelID) {
        guard offlineASRModels.contains(where: { $0.id == id }) else { return }
        offlineASRModelID = id
        modelPreparationState = modelPreparationCenter?.state(for: id) ?? .notPrepared
        savePipelineOptions()
    }

    func selectOfflineJobSchedule(_ schedule: OfflineJobSchedule) {
        offlineJobSchedule = schedule
        savePipelineOptions()
    }

    func prepareSelectedOfflineASRModel() {
        modelPreparationCenter?.prepare(offlineASRModelID)
    }

    func prepareOnlineDraftModels() {
        guard let onlineDraftCoordinator else { return }
        Task { await onlineDraftCoordinator.prepareModels() }
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
                offlineASRModelID: offlineASRModelID,
                offlineJobSchedule: offlineJobSchedule,
                languageCode: "ru-RU",
                ctcMode: ctcMode,
                isLLMCorrectionEnabled: isLLMCorrectionEnabled,
                offlineDiarization: offlineDiarization,
                voiceBankMatching: voiceBankMatching
            )
        )
    }
}
