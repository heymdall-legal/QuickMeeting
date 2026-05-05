import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct TranscriptionModelManagerTests {
    @Test
    func refreshReportsInstalledModelsFromStore() async {
        let store = FakeWhisperModelStore(
            installed: [.tiny: .mockInstalled(sizeInBytes: 512)]
        )
        let settings = UserDefaults(suiteName: #function)!
        settings.removePersistentDomain(forName: #function)
        let manager = TranscriptionModelManager(
            modelStore: store,
            settingsStore: ModelSettingsStore(userDefaults: settings)
        )

        let statuses = await manager.refreshStatuses()

        #expect(statuses[.tiny] == .installed(sizeInBytes: 512, installedAt: nil))
        #expect(statuses[.small] == .notInstalled)
        #expect(statuses[.largeV3] == .notInstalled)
    }

    @Test
    func firstSuccessfulDownloadBecomesDefaultModel() async throws {
        let settings = UserDefaults(suiteName: #function)!
        settings.removePersistentDomain(forName: #function)
        let manager = TranscriptionModelManager(
            modelStore: FakeWhisperModelStore(),
            settingsStore: ModelSettingsStore(userDefaults: settings)
        )

        try await manager.download(.small)

        #expect(manager.currentDefaultModelID == .small)
        #expect(manager.statuses[.small] == .installed(sizeInBytes: 1_024, installedAt: nil))
    }

    @Test
    func deletingDefaultModelPromotesNextInstalledModel() async throws {
        let store = FakeWhisperModelStore(
            installed: [
                .small: .mockInstalled(sizeInBytes: 128),
                .largeV3: .mockInstalled(sizeInBytes: 256),
            ]
        )
        let settings = UserDefaults(suiteName: #function)!
        settings.removePersistentDomain(forName: #function)
        let settingsStore = ModelSettingsStore(userDefaults: settings)
        settingsStore.defaultModelID = .small
        let manager = TranscriptionModelManager(
            modelStore: store,
            settingsStore: settingsStore
        )

        _ = await manager.refreshStatuses()
        try await manager.delete(.small)

        #expect(manager.currentDefaultModelID == .largeV3)
        #expect(manager.statuses[.small] == .notInstalled)
        #expect(manager.statuses[.largeV3] == .installed(sizeInBytes: 256, installedAt: nil))
    }

    @Test
    func failedDownloadSetsFailedStatus() async {
        let settings = UserDefaults(suiteName: #function)!
        settings.removePersistentDomain(forName: #function)
        let manager = TranscriptionModelManager(
            modelStore: FakeWhisperModelStore(downloadError: FakeWhisperModelStore.TestError.network),
            settingsStore: ModelSettingsStore(userDefaults: settings)
        )

        await #expect(throws: FakeWhisperModelStore.TestError.network) {
            try await manager.download(.largeV3)
        }

        #expect(manager.statuses[.largeV3] == .failed(message: FakeWhisperModelStore.TestError.network.localizedDescription))
        #expect(manager.currentDefaultModelID == nil)
    }
}

private actor FakeWhisperModelStore: WhisperModelStore {
    enum TestError: Error, LocalizedError {
        case network

        var errorDescription: String? {
            switch self {
            case .network:
                return "Network unavailable"
            }
        }
    }

    var installed: [TranscriptionModelID: InstalledTranscriptionModel]
    let downloadError: Error?

    init(
        installed: [TranscriptionModelID: InstalledTranscriptionModel] = [:],
        downloadError: Error? = nil
    ) {
        self.installed = installed
        self.downloadError = downloadError
    }

    func installedModels() async throws -> [TranscriptionModelID: InstalledTranscriptionModel] {
        installed
    }

    func downloadModel(
        _ model: TranscriptionModel,
        onProgress _: @escaping @Sendable (Double?) -> Void
    ) async throws {
        if let downloadError {
            throw downloadError
        }

        installed[model.id] = InstalledTranscriptionModel(sizeInBytes: 1_024, installedAt: nil)
    }

    func deleteModel(_ model: TranscriptionModel) async throws {
        installed.removeValue(forKey: model.id)
    }
}

private extension InstalledTranscriptionModel {
    static func mockInstalled(sizeInBytes: Int64) -> InstalledTranscriptionModel {
        InstalledTranscriptionModel(sizeInBytes: sizeInBytes, installedAt: nil)
    }
}
