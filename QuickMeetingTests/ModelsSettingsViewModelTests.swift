import Foundation
import Combine
import Testing
@testable import QuickMeeting

@MainActor
struct ModelsSettingsViewModelTests {
    @Test
    func loadBuildsRowsInCatalogOrder() async {
        let viewModel = ModelsSettingsViewModel(
            manager: FakeTranscriptionModelManaging(
                statuses: [
                    .tiny: .notInstalled,
                    .small: .installed(sizeInBytes: 1_024, installedAt: nil),
                    .largeV3: .notInstalled,
                ],
                defaultModelID: .small
            )
        )

        await viewModel.load()

        #expect(viewModel.rows.map(\.model.id) == [.tiny, .small, .largeV3])
        #expect(viewModel.defaultModelID == .small)
    }

    @Test
    func downloadFailureSetsErrorMessage() async {
        let viewModel = ModelsSettingsViewModel(
            manager: FakeTranscriptionModelManaging(
                downloadError: FakeTranscriptionModelManaging.TestError.network
            )
        )

        await viewModel.download(.tiny)

        #expect(viewModel.errorMessage == FakeTranscriptionModelManaging.TestError.network.localizedDescription)
    }

    @Test
    func progressUpdatesFlowIntoRowsWhileDownloadIsRunning() async {
        let manager = FakeTranscriptionModelManaging(
            statuses: [
                .tiny: .notInstalled,
                .small: .notInstalled,
                .largeV3: .notInstalled,
            ]
        )
        let viewModel = ModelsSettingsViewModel(manager: manager)
        await viewModel.load()

        manager.pushStatus(.tiny, state: .downloading(progress: 0.42))
        await Task.yield()

        let tinyRow = viewModel.rows.first { $0.model.id == .tiny }
        #expect(tinyRow?.state == .downloading(progress: 0.42))
    }
}

@MainActor
private final class FakeTranscriptionModelManaging: TranscriptionModelManaging {
    enum TestError: Error, LocalizedError {
        case network

        var errorDescription: String? {
            switch self {
            case .network:
                return "Network unavailable"
            }
        }
    }

    var currentStatuses: [TranscriptionModelID: TranscriptionModelInstallState] {
        statuses
    }

    var statusesPublisher: AnyPublisher<[TranscriptionModelID: TranscriptionModelInstallState], Never> {
        statusesSubject.eraseToAnyPublisher()
    }

    var currentDefaultModelID: TranscriptionModelID?
    var statuses: [TranscriptionModelID: TranscriptionModelInstallState]
    let downloadError: Error?
    private let statusesSubject: CurrentValueSubject<[TranscriptionModelID: TranscriptionModelInstallState], Never>

    init(
        statuses: [TranscriptionModelID: TranscriptionModelInstallState] = [:],
        defaultModelID: TranscriptionModelID? = nil,
        downloadError: Error? = nil
    ) {
        self.statuses = statuses
        self.currentDefaultModelID = defaultModelID
        self.downloadError = downloadError
        self.statusesSubject = CurrentValueSubject(statuses)
    }

    func refreshStatuses() async -> [TranscriptionModelID: TranscriptionModelInstallState] {
        statuses
    }

    func download(_ modelID: TranscriptionModelID) async throws {
        if let downloadError {
            throw downloadError
        }

        statuses[modelID] = .installed(sizeInBytes: 1_024, installedAt: nil)
        statusesSubject.send(statuses)
        if currentDefaultModelID == nil {
            currentDefaultModelID = modelID
        }
    }

    func delete(_ modelID: TranscriptionModelID) async throws {
        statuses[modelID] = .notInstalled
        statusesSubject.send(statuses)
        if currentDefaultModelID == modelID {
            currentDefaultModelID = nil
        }
    }

    func setDefaultModelID(_ modelID: TranscriptionModelID?) async {
        currentDefaultModelID = modelID
    }

    func pushStatus(_ modelID: TranscriptionModelID, state: TranscriptionModelInstallState) {
        statuses[modelID] = state
        statusesSubject.send(statuses)
    }
}
