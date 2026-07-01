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
    @Published private(set) var isRealtimeTranscriptionEnabled: Bool
    @Published private(set) var realtimeTranscriptionBackend: RealtimeTranscriptionBackend
    @Published private(set) var realtimeTranscriptionEndpointURLString: String
    @Published private(set) var realtimeTranscriptionModelName: String
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
        isRealtimeTranscriptionEnabled = options.isRealtimeTranscriptionEnabled
        realtimeTranscriptionBackend = options.realtimeTranscriptionBackend
        realtimeTranscriptionEndpointURLString = options.realtimeTranscriptionEndpointURLString
        realtimeTranscriptionModelName = options.realtimeTranscriptionModelName
        glossaryTerms = []
        isGlossaryLoaded = false
    }

    var options: [TranscriptionLanguageOption] { TranscriptionLanguageOption.all }
    var ctcOptions: [TranscriptionCTCMode] { TranscriptionCTCMode.allCases }
    var realtimeBackendOptions: [RealtimeTranscriptionBackend] { RealtimeTranscriptionBackend.allCases }

    var selectedLanguageName: String { TranscriptionLanguageOption.name(for: languageCode) }

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

    func setRealtimeTranscriptionEnabled(_ isEnabled: Bool) {
        isRealtimeTranscriptionEnabled = isEnabled
        savePipelineOptions()
    }

    func selectRealtimeTranscriptionBackend(_ backend: RealtimeTranscriptionBackend) {
        realtimeTranscriptionBackend = backend
        savePipelineOptions()
    }

    func setRealtimeTranscriptionEndpointURLString(_ endpointURLString: String) {
        realtimeTranscriptionEndpointURLString = endpointURLString
        savePipelineOptions()
    }

    func setRealtimeTranscriptionModelName(_ modelName: String) {
        realtimeTranscriptionModelName = modelName
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
                isRealtimeTranscriptionEnabled: isRealtimeTranscriptionEnabled,
                realtimeTranscriptionBackend: realtimeTranscriptionBackend,
                realtimeTranscriptionEndpointURLString: realtimeTranscriptionEndpointURLString,
                realtimeTranscriptionModelName: realtimeTranscriptionModelName
            )
        )
    }
}
