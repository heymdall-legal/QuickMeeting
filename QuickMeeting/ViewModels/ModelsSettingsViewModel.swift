//
//  ModelsSettingsViewModel.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Combine
import Foundation

protocol TranscriptionModelManaging: AnyObject {
    var currentDefaultModelID: TranscriptionModelID? { get }
    var currentStatuses: [TranscriptionModelID: TranscriptionModelInstallState] { get }
    var statusesPublisher: AnyPublisher<[TranscriptionModelID: TranscriptionModelInstallState], Never> { get }
    func refreshStatuses() async -> [TranscriptionModelID: TranscriptionModelInstallState]
    func download(_ modelID: TranscriptionModelID) async throws
    func delete(_ modelID: TranscriptionModelID) async throws
    func setDefaultModelID(_ modelID: TranscriptionModelID?) async
}

struct TranscriptionModelRow: Identifiable, Equatable {
    let id: TranscriptionModelID
    let model: TranscriptionModel
    let state: TranscriptionModelInstallState
}

@MainActor
final class ModelsSettingsViewModel: ObservableObject {
    @Published private(set) var rows = [TranscriptionModelRow]()
    @Published private(set) var isLoading = true
    @Published var defaultModelID: TranscriptionModelID?
    @Published var errorMessage: String?

    private let manager: TranscriptionModelManaging
    private var cancellables = Set<AnyCancellable>()

    init(manager: TranscriptionModelManaging) {
        self.manager = manager
        self.defaultModelID = manager.currentDefaultModelID
        bindManagerUpdates()
    }

    func load() async {
        let statuses = await manager.refreshStatuses()
        applyStatuses(statuses)
        defaultModelID = manager.currentDefaultModelID
        isLoading = false
    }

    func download(_ modelID: TranscriptionModelID) async {
        do {
            try await manager.download(modelID)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    func delete(_ modelID: TranscriptionModelID) async {
        do {
            try await manager.delete(modelID)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateDefaultModel(_ modelID: TranscriptionModelID?) async {
        await manager.setDefaultModelID(modelID)
        defaultModelID = manager.currentDefaultModelID
    }

    func clearError() {
        errorMessage = nil
    }

    private func bindManagerUpdates() {
        manager.statusesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statuses in
                self?.applyStatuses(statuses)
            }
            .store(in: &cancellables)
    }

    private func applyStatuses(_ statuses: [TranscriptionModelID: TranscriptionModelInstallState]) {
        rows = TranscriptionModelCatalog.supportedModels.map { model in
            TranscriptionModelRow(
                id: model.id,
                model: model,
                state: statuses[model.id] ?? .notInstalled
            )
        }
    }
}
