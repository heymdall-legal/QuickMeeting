import Combine
import Foundation

nonisolated enum TranscriptionModelPreparationState: Equatable, Sendable {
    case notPrepared
    case preparing(progress: Double, phase: String)
    case ready
    case failed(message: String)

    var progress: Double? {
        guard case .preparing(let progress, _) = self else { return nil }
        return progress
    }
}

@MainActor
final class TranscriptionModelPreparationCenter: ObservableObject {
    @Published private(set) var stateByModel: [OfflineASRModelID: TranscriptionModelPreparationState]

    private let preparer: any ASRModelPreparing
    private var preparationTasks: [OfflineASRModelID: Task<Void, Never>] = [:]

    init(preparer: any ASRModelPreparing) {
        self.preparer = preparer
        stateByModel = Dictionary(
            uniqueKeysWithValues: OfflineASRModelCatalog.selectable.map { ($0.id, .notPrepared) }
        )
    }

    func state(for modelID: OfflineASRModelID) -> TranscriptionModelPreparationState {
        stateByModel[modelID] ?? .failed(message: "Backend is unavailable")
    }

    func prepare(_ modelID: OfflineASRModelID) {
        guard preparationTasks[modelID] == nil,
              OfflineASRModelCatalog.selectable.contains(where: { $0.id == modelID }) else {
            return
        }

        stateByModel[modelID] = .preparing(progress: 0, phase: "Preparing")
        let preparer = preparer
        preparationTasks[modelID] = Task { [self] in
            do {
                try await preparer.prepare(modelID: modelID) { progress, phase in
                    Task { @MainActor [self] in
                        self.stateByModel[modelID] = .preparing(
                            progress: min(max(progress, 0), 1),
                            phase: phase
                        )
                    }
                }
                guard !Task.isCancelled else { return }
                stateByModel[modelID] = .ready
            } catch is CancellationError {
                stateByModel[modelID] = .notPrepared
            } catch {
                stateByModel[modelID] = .failed(message: error.localizedDescription)
            }
            preparationTasks[modelID] = nil
        }
    }

    func cancelPreparation(_ modelID: OfflineASRModelID) {
        preparationTasks[modelID]?.cancel()
        preparationTasks[modelID] = nil
        if case .preparing = stateByModel[modelID] {
            stateByModel[modelID] = .notPrepared
        }
    }
}
