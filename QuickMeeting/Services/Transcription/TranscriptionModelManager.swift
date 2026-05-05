//
//  TranscriptionModelManager.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Combine
import Foundation

@MainActor
final class TranscriptionModelManager: ObservableObject {
    @Published private(set) var statuses: [TranscriptionModelID: TranscriptionModelInstallState]

    private let modelStore: WhisperModelStore
    private let settingsStore: ModelSettingsStore
    private var activeDownloadModelID: TranscriptionModelID?

    init(
        modelStore: WhisperModelStore,
        settingsStore: ModelSettingsStore
    ) {
        self.modelStore = modelStore
        self.settingsStore = settingsStore
        self.statuses = Dictionary(
            uniqueKeysWithValues: TranscriptionModelCatalog.supportedModels.map { ($0.id, .notInstalled) }
        )
    }

    var currentDefaultModelID: TranscriptionModelID? {
        settingsStore.defaultModelID
    }

    var currentStatuses: [TranscriptionModelID: TranscriptionModelInstallState] {
        statuses
    }

    var statusesPublisher: AnyPublisher<[TranscriptionModelID: TranscriptionModelInstallState], Never> {
        $statuses.eraseToAnyPublisher()
    }

    func refreshStatuses() async -> [TranscriptionModelID: TranscriptionModelInstallState] {
        let installedModels = (try? await modelStore.installedModels()) ?? [:]
        var nextStatuses = [TranscriptionModelID: TranscriptionModelInstallState]()

        for model in TranscriptionModelCatalog.supportedModels {
            if let metadata = installedModels[model.id] {
                nextStatuses[model.id] = .installed(
                    sizeInBytes: metadata.sizeInBytes,
                    installedAt: metadata.installedAt
                )
            } else {
                nextStatuses[model.id] = .notInstalled
            }
        }

        statuses = nextStatuses
        reconcileDefaultModel(using: installedModels)
        return nextStatuses
    }

    func download(_ modelID: TranscriptionModelID) async throws {
        guard activeDownloadModelID == nil else {
            return
        }

        guard let model = TranscriptionModelCatalog.model(for: modelID) else {
            return
        }

        activeDownloadModelID = modelID
        statuses[modelID] = .downloading(progress: nil)

        do {
            try await modelStore.downloadModel(model) { progress in
                Task { @MainActor [weak self, modelID] in
                    self?.statuses[modelID] = .downloading(progress: progress)
                }
            }

            _ = await refreshStatuses()
            if settingsStore.defaultModelID == nil {
                settingsStore.defaultModelID = modelID
            }
            activeDownloadModelID = nil
        } catch {
            statuses[modelID] = .failed(message: error.localizedDescription)
            activeDownloadModelID = nil
            throw error
        }
    }

    func delete(_ modelID: TranscriptionModelID) async throws {
        guard let model = TranscriptionModelCatalog.model(for: modelID) else {
            return
        }

        let deletedModelWasDefault = settingsStore.defaultModelID == modelID
        try await modelStore.deleteModel(model)
        let refreshedStatuses = await refreshStatuses()

        guard deletedModelWasDefault else {
            return
        }

        settingsStore.defaultModelID = TranscriptionModelCatalog.supportedModels.first(where: {
            if case .installed = refreshedStatuses[$0.id] {
                return true
            }

            return false
        })?.id
    }

    private func reconcileDefaultModel(
        using installedModels: [TranscriptionModelID: InstalledTranscriptionModel]
    ) {
        guard let defaultModelID = settingsStore.defaultModelID else {
            return
        }

        guard installedModels[defaultModelID] != nil else {
            settingsStore.defaultModelID = nil
            return
        }
    }
}

extension TranscriptionModelManager: TranscriptionModelManaging {
    func setDefaultModelID(_ modelID: TranscriptionModelID?) async {
        guard let modelID else {
            settingsStore.defaultModelID = nil
            return
        }

        if case .installed = statuses[modelID] {
            settingsStore.defaultModelID = modelID
        }
    }
}
