**Goal:** Build a dedicated macOS Settings window with a `Models` pane that lets users download, delete, inspect, and choose a default transcription model for the supported Argmax Whisper models.

**Architecture:** Keep model management behind app-owned types and protocols so SwiftUI never depends directly on Argmax APIs. The implementation should derive installed state from disk through an Argmax adapter, persist only the default model selection in settings storage, and expose everything to the UI through a focused `ModelsSettingsViewModel`.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest, `argmax-oss-swift`

---

### File Structure

**Create:**
- `QuickMeeting/Models/TranscriptionModel.swift`
- `QuickMeeting/Services/Transcription/TranscriptionModelCatalog.swift`
- `QuickMeeting/Services/Transcription/ModelSettingsStore.swift`
- `QuickMeeting/Services/Transcription/ArgmaxWhisperModelStore.swift`
- `QuickMeeting/Services/Transcription/TranscriptionModelManager.swift`
- `QuickMeeting/ViewModels/ModelsSettingsViewModel.swift`
- `QuickMeeting/Views/Settings/SettingsView.swift`
- `QuickMeeting/Views/Settings/ModelsSettingsView.swift`
- `QuickMeetingTests/TranscriptionModelCatalogTests.swift`
- `QuickMeetingTests/ModelSettingsStoreTests.swift`
- `QuickMeetingTests/TranscriptionModelManagerTests.swift`
- `QuickMeetingTests/ModelsSettingsViewModelTests.swift`

**Modify:**
- `QuickMeeting/QuickMeetingApp.swift`
- `QuickMeeting.xcodeproj/project.pbxproj`

**Responsibilities:**
- `TranscriptionModel.swift`: App-owned identifiers and row state types for supported models.
- `TranscriptionModelCatalog.swift`: Fixed supported-model list, Argmax IDs, labels, and descriptions.
- `ModelSettingsStore.swift`: Persist and validate the default model selection with `UserDefaults`.
- `ArgmaxWhisperModelStore.swift`: Package-specific model discovery, download, and deletion adapter.
- `TranscriptionModelManager.swift`: Orchestrate state refresh, single active download, deletion rules, and default-model behavior.
- `ModelsSettingsViewModel.swift`: UI-facing model rows, actions, loading, and user-visible errors.
- `SettingsView.swift`: Sidebar-based settings shell for future panes.
- `ModelsSettingsView.swift`: Concrete `Models` pane UI.
- Test files: Cover catalog, persistence, manager orchestration, and view-model behavior.

### Task 1: Define supported model types and settings persistence

**Files:**
- Create: `QuickMeeting/Models/TranscriptionModel.swift`
- Create: `QuickMeeting/Services/Transcription/TranscriptionModelCatalog.swift`
- Create: `QuickMeeting/Services/Transcription/ModelSettingsStore.swift`
- Test: `QuickMeetingTests/TranscriptionModelCatalogTests.swift`
- Test: `QuickMeetingTests/ModelSettingsStoreTests.swift`
- Modify: `QuickMeeting.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing catalog tests**

```swift
import XCTest
@testable import QuickMeeting

final class TranscriptionModelCatalogTests: XCTestCase {
    func test_supportedModels_arePinnedAndSorted() {
        let models = TranscriptionModelCatalog.supportedModels

        XCTAssertEqual(models.map(\.id), [.tiny, .small, .largeV3])
        XCTAssertEqual(models.map(\.argmaxModelID), [
            "tiny",
            "small",
            "large-v3-v20240930_626MB",
        ])
        XCTAssertEqual(models.map(\.displayName), [
            "Tiny",
            "Small",
            "Large v3",
        ])
    }
}
```

- [ ] **Step 2: Write the failing settings-store tests**

```swift
import XCTest
@testable import QuickMeeting

final class ModelSettingsStoreTests: XCTestCase {
    func test_defaultModel_roundTripsStoredValue() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = ModelSettingsStore(userDefaults: defaults)

        XCTAssertNil(store.defaultModelID)

        store.defaultModelID = .small

        XCTAssertEqual(store.defaultModelID, .small)
    }

    func test_clearInvalidSelection_removesUnsupportedValue() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("unsupported-model", forKey: "defaultTranscriptionModelID")
        let store = ModelSettingsStore(userDefaults: defaults)

        XCTAssertNil(store.defaultModelID)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task-models CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionModelCatalogTests -only-testing:QuickMeetingTests/ModelSettingsStoreTests`

Expected: FAIL with missing `TranscriptionModelCatalog`, `TranscriptionModel`, or `ModelSettingsStore` symbols.

- [ ] **Step 4: Add the supported model types**

```swift
import Foundation

enum TranscriptionModelID: String, CaseIterable, Codable, Sendable {
    case tiny
    case small
    case largeV3
}

struct TranscriptionModel: Identifiable, Equatable, Sendable {
    let id: TranscriptionModelID
    let displayName: String
    let argmaxModelID: String
    let summary: String
    let sortOrder: Int
}

enum TranscriptionModelInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double?)
    case installed(sizeInBytes: Int64, installedAt: Date?)
    case failed(message: String)
}
```

- [ ] **Step 5: Add the fixed model catalog**

```swift
import Foundation

enum TranscriptionModelCatalog {
    static let supportedModels: [TranscriptionModel] = [
        TranscriptionModel(
            id: .tiny,
            displayName: "Tiny",
            argmaxModelID: "tiny",
            summary: "Fastest download and best for debugging or quick tests.",
            sortOrder: 0
        ),
        TranscriptionModel(
            id: .small,
            displayName: "Small",
            argmaxModelID: "small",
            summary: "Balanced speed and accuracy for everyday use.",
            sortOrder: 1
        ),
        TranscriptionModel(
            id: .largeV3,
            displayName: "Large v3",
            argmaxModelID: "large-v3-v20240930_626MB",
            summary: "Highest accuracy, largest download, best for production-quality transcription.",
            sortOrder: 2
        ),
    ]

    static func model(for id: TranscriptionModelID) -> TranscriptionModel? {
        supportedModels.first { $0.id == id }
    }
}
```

- [ ] **Step 6: Add the settings store**

```swift
import Foundation

final class ModelSettingsStore {
    private let userDefaults: UserDefaults
    private let defaultModelKey = "defaultTranscriptionModelID"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var defaultModelID: TranscriptionModelID? {
        get {
            guard let rawValue = userDefaults.string(forKey: defaultModelKey) else {
                return nil
            }

            return TranscriptionModelID(rawValue: rawValue)
        }
        set {
            userDefaults.set(newValue?.rawValue, forKey: defaultModelKey)
        }
    }
}
```

- [ ] **Step 7: Add the new files to the Xcode project**

```pbxproj
/* Add file references and build file entries for:
   - QuickMeeting/Models/TranscriptionModel.swift
   - QuickMeeting/Services/Transcription/TranscriptionModelCatalog.swift
   - QuickMeeting/Services/Transcription/ModelSettingsStore.swift
   - QuickMeetingTests/TranscriptionModelCatalogTests.swift
   - QuickMeetingTests/ModelSettingsStoreTests.swift
*/
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task-models CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionModelCatalogTests -only-testing:QuickMeetingTests/ModelSettingsStoreTests`

Expected: PASS for both new test classes.

- [ ] **Step 9: Commit**

```bash
git add QuickMeeting/Models/TranscriptionModel.swift \
  QuickMeeting/Services/Transcription/TranscriptionModelCatalog.swift \
  QuickMeeting/Services/Transcription/ModelSettingsStore.swift \
  QuickMeetingTests/TranscriptionModelCatalogTests.swift \
  QuickMeetingTests/ModelSettingsStoreTests.swift \
  QuickMeeting.xcodeproj/project.pbxproj
git commit -m "feat: add transcription model catalog and settings store"
```

### Task 2: Add the model store and orchestration manager

**Files:**
- Create: `QuickMeeting/Services/Transcription/ArgmaxWhisperModelStore.swift`
- Create: `QuickMeeting/Services/Transcription/TranscriptionModelManager.swift`
- Test: `QuickMeetingTests/TranscriptionModelManagerTests.swift`
- Modify: `QuickMeeting.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing manager tests**

```swift
import XCTest
@testable import QuickMeeting

@MainActor
final class TranscriptionModelManagerTests: XCTestCase {
    func test_refresh_reportsInstalledModelsFromStore() async throws {
        let store = FakeWhisperModelStore(
            installed: [.tiny: .mockInstalled(sizeInBytes: 512)]
        )
        let settings = ModelSettingsStore(userDefaults: UserDefaults(suiteName: #function)!)
        let manager = TranscriptionModelManager(modelStore: store, settingsStore: settings)

        let statuses = await manager.refreshStatuses()

        XCTAssertEqual(statuses[.tiny], .installed(sizeInBytes: 512, installedAt: nil))
        XCTAssertEqual(statuses[.small], .notInstalled)
    }

    func test_downloadFirstInstalledModel_setsDefaultWhenMissing() async throws {
        let store = FakeWhisperModelStore()
        let settings = ModelSettingsStore(userDefaults: UserDefaults(suiteName: #function)!)
        let manager = TranscriptionModelManager(modelStore: store, settingsStore: settings)

        try await manager.download(.small)

        XCTAssertEqual(settings.defaultModelID, .small)
    }

    func test_deleteDefaultModel_promotesNextInstalledModel() async throws {
        let store = FakeWhisperModelStore(
            installed: [
                .small: .mockInstalled(sizeInBytes: 128),
                .largeV3: .mockInstalled(sizeInBytes: 256),
            ]
        )
        let settings = ModelSettingsStore(userDefaults: UserDefaults(suiteName: #function)!)
        settings.defaultModelID = .small
        let manager = TranscriptionModelManager(modelStore: store, settingsStore: settings)

        try await manager.delete(.small)

        XCTAssertEqual(settings.defaultModelID, .largeV3)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task-models CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionModelManagerTests`

Expected: FAIL with missing `TranscriptionModelManager`, `WhisperModelStore`, or helper types.

- [ ] **Step 3: Define the model-store protocol and disk metadata**

```swift
import Foundation

struct InstalledTranscriptionModel: Equatable, Sendable {
    let sizeInBytes: Int64
    let installedAt: Date?
}

protocol WhisperModelStore: Sendable {
    func installedModels() async throws -> [TranscriptionModelID: InstalledTranscriptionModel]
    func downloadModel(
        _ model: TranscriptionModel,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws
    func deleteModel(_ model: TranscriptionModel) async throws
}
```

- [ ] **Step 4: Add the manager orchestration**

```swift
import Foundation

@MainActor
final class TranscriptionModelManager: ObservableObject {
    @Published private(set) var statuses: [TranscriptionModelID: TranscriptionModelInstallState] = [:]

    private let modelStore: WhisperModelStore
    private let settingsStore: ModelSettingsStore
    private var activeDownloadID: TranscriptionModelID?

    init(modelStore: WhisperModelStore, settingsStore: ModelSettingsStore) {
        self.modelStore = modelStore
        self.settingsStore = settingsStore
    }

    func refreshStatuses() async -> [TranscriptionModelID: TranscriptionModelInstallState] {
        let installed = (try? await modelStore.installedModels()) ?? [:]
        var newStatuses: [TranscriptionModelID: TranscriptionModelInstallState] = [:]

        for model in TranscriptionModelCatalog.supportedModels {
            if let metadata = installed[model.id] {
                newStatuses[model.id] = .installed(
                    sizeInBytes: metadata.sizeInBytes,
                    installedAt: metadata.installedAt
                )
            } else {
                newStatuses[model.id] = .notInstalled
            }
        }

        statuses = newStatuses
        reconcileDefaultModel(withInstalled: installed)
        return newStatuses
    }

    func download(_ modelID: TranscriptionModelID) async throws {
        guard activeDownloadID == nil else { return }
        guard let model = TranscriptionModelCatalog.model(for: modelID) else { return }

        activeDownloadID = modelID
        statuses[modelID] = .downloading(progress: nil)

        do {
            try await modelStore.downloadModel(model) { [weak self] progress in
                Task { @MainActor in
                    self?.statuses[modelID] = .downloading(progress: progress)
                }
            }

            _ = await refreshStatuses()
            if settingsStore.defaultModelID == nil {
                settingsStore.defaultModelID = modelID
            }
            activeDownloadID = nil
        } catch {
            statuses[modelID] = .failed(message: error.localizedDescription)
            activeDownloadID = nil
            throw error
        }
    }

    func delete(_ modelID: TranscriptionModelID) async throws {
        guard let model = TranscriptionModelCatalog.model(for: modelID) else { return }
        try await modelStore.deleteModel(model)
        let statuses = await refreshStatuses()
        if settingsStore.defaultModelID == modelID {
            let replacement = TranscriptionModelCatalog.supportedModels.first {
                if case .installed = statuses[$0.id] { return true }
                return false
            }
            settingsStore.defaultModelID = replacement?.id
        }
    }

    private func reconcileDefaultModel(
        withInstalled installed: [TranscriptionModelID: InstalledTranscriptionModel]
    ) {
        guard let defaultModelID = settingsStore.defaultModelID else { return }
        if installed[defaultModelID] == nil {
            settingsStore.defaultModelID = nil
        }
    }
}
```

- [ ] **Step 5: Add a fake store for tests and make the tests pass**

```swift
private actor FakeWhisperModelStore: WhisperModelStore {
    var installed: [TranscriptionModelID: InstalledTranscriptionModel]

    init(installed: [TranscriptionModelID: InstalledTranscriptionModel] = [:]) {
        self.installed = installed
    }

    func installedModels() async throws -> [TranscriptionModelID: InstalledTranscriptionModel] {
        installed
    }

    func downloadModel(
        _ model: TranscriptionModel,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        onProgress(0.5)
        installed[model.id] = InstalledTranscriptionModel(sizeInBytes: 1_024, installedAt: nil)
        onProgress(1.0)
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
```

- [ ] **Step 6: Add the new files to the Xcode project**

```pbxproj
/* Add file references and build file entries for:
   - QuickMeeting/Services/Transcription/ArgmaxWhisperModelStore.swift
   - QuickMeeting/Services/Transcription/TranscriptionModelManager.swift
   - QuickMeetingTests/TranscriptionModelManagerTests.swift
*/
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task-models CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionModelManagerTests`

Expected: PASS for manager refresh, download, and delete behavior.

- [ ] **Step 8: Commit**

```bash
git add QuickMeeting/Services/Transcription/ArgmaxWhisperModelStore.swift \
  QuickMeeting/Services/Transcription/TranscriptionModelManager.swift \
  QuickMeetingTests/TranscriptionModelManagerTests.swift \
  QuickMeeting.xcodeproj/project.pbxproj
git commit -m "feat: add transcription model manager"
```

### Task 3: Implement the Argmax adapter behind the model-store protocol

**Files:**
- Modify: `QuickMeeting/Services/Transcription/ArgmaxWhisperModelStore.swift`
- Test: `QuickMeetingTests/TranscriptionModelManagerTests.swift`

- [ ] **Step 1: Extend tests to cover adapter-facing error translation indirectly**

```swift
func test_downloadFailure_setsFailedStatusAndPreservesRetry() async {
    let store = FakeWhisperModelStore(downloadError: TestError.network)
    let settings = ModelSettingsStore(userDefaults: UserDefaults(suiteName: #function)!)
    let manager = TranscriptionModelManager(modelStore: store, settingsStore: settings)

    await XCTAssertThrowsErrorAsync {
        try await manager.download(.largeV3)
    }

    XCTAssertEqual(manager.statuses[.largeV3], .failed(message: TestError.network.localizedDescription))
}
```

- [ ] **Step 2: Run the targeted test to verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task-models CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionModelManagerTests/test_downloadFailure_setsFailedStatusAndPreservesRetry`

Expected: FAIL because the fake store does not yet support error injection or the manager does not preserve the failed state correctly.

- [ ] **Step 3: Implement the real adapter skeleton with local inspection hooks**

```swift
import Foundation
import WhisperKit

struct ArgmaxWhisperModelStore: WhisperModelStore {
    let fileManager: FileManager
    let modelsRootURL: URL

    init(
        fileManager: FileManager = .default,
        modelsRootURL: URL = WhisperKit.recommendedModelsURL()
    ) {
        self.fileManager = fileManager
        self.modelsRootURL = modelsRootURL
    }

    func installedModels() async throws -> [TranscriptionModelID: InstalledTranscriptionModel] {
        var installed: [TranscriptionModelID: InstalledTranscriptionModel] = [:]

        for model in TranscriptionModelCatalog.supportedModels {
            let modelURL = modelsRootURL.appendingPathComponent("openai_whisper-\(model.argmaxModelID)")
            guard fileManager.fileExists(atPath: modelURL.path()) else { continue }

            let size = try directorySize(at: modelURL)
            let attributes = try fileManager.attributesOfItem(atPath: modelURL.path())
            let installedAt = attributes[.creationDate] as? Date
            installed[model.id] = InstalledTranscriptionModel(sizeInBytes: size, installedAt: installedAt)
        }

        return installed
    }

    func downloadModel(
        _ model: TranscriptionModel,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        onProgress(nil)
        _ = try await WhisperKit(WhisperKitConfig(model: model.argmaxModelID))
        onProgress(1.0)
    }

    func deleteModel(_ model: TranscriptionModel) async throws {
        let modelURL = modelsRootURL.appendingPathComponent("openai_whisper-\(model.argmaxModelID)")
        guard fileManager.fileExists(atPath: modelURL.path()) else { return }
        try fileManager.removeItem(at: modelURL)
    }

    private func directorySize(at url: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        var total: Int64 = 0

        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: keys)
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }

        return total
    }
}
```

- [ ] **Step 4: Update the fake store and manager test helper**

```swift
private actor FakeWhisperModelStore: WhisperModelStore {
    enum TestError: LocalizedError { case network }

    var installed: [TranscriptionModelID: InstalledTranscriptionModel]
    let downloadError: Error?

    init(
        installed: [TranscriptionModelID: InstalledTranscriptionModel] = [:],
        downloadError: Error? = nil
    ) {
        self.installed = installed
        self.downloadError = downloadError
    }

    func downloadModel(
        _ model: TranscriptionModel,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        if let downloadError {
            throw downloadError
        }

        onProgress(0.5)
        installed[model.id] = InstalledTranscriptionModel(sizeInBytes: 1_024, installedAt: nil)
        onProgress(1.0)
    }
}
```

- [ ] **Step 5: Run the manager tests to verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task-models CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionModelManagerTests`

Expected: PASS including the failed-download case.

- [ ] **Step 6: Commit**

```bash
git add QuickMeeting/Services/Transcription/ArgmaxWhisperModelStore.swift \
  QuickMeetingTests/TranscriptionModelManagerTests.swift
git commit -m "feat: add argmax whisper model store"
```

### Task 4: Add the models settings view model

**Files:**
- Create: `QuickMeeting/ViewModels/ModelsSettingsViewModel.swift`
- Test: `QuickMeetingTests/ModelsSettingsViewModelTests.swift`
- Modify: `QuickMeeting.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing view-model tests**

```swift
import XCTest
@testable import QuickMeeting

@MainActor
final class ModelsSettingsViewModelTests: XCTestCase {
    func test_load_buildsRowsInCatalogOrder() async {
        let manager = FakeTranscriptionModelManager(
            statuses: [
                .tiny: .notInstalled,
                .small: .installed(sizeInBytes: 1_024, installedAt: nil),
                .largeV3: .notInstalled,
            ],
            defaultModelID: .small
        )
        let viewModel = ModelsSettingsViewModel(manager: manager)

        await viewModel.load()

        XCTAssertEqual(viewModel.rows.map(\.model.id), [.tiny, .small, .largeV3])
        XCTAssertEqual(viewModel.defaultModelID, .small)
    }

    func test_downloadFailure_setsErrorMessage() async {
        let manager = FakeTranscriptionModelManager(downloadError: TestError.network)
        let viewModel = ModelsSettingsViewModel(manager: manager)

        await viewModel.download(.tiny)

        XCTAssertEqual(viewModel.errorMessage, TestError.network.localizedDescription)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task-models CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/ModelsSettingsViewModelTests`

Expected: FAIL with missing `ModelsSettingsViewModel` or manager protocol symbols.

- [ ] **Step 3: Add the UI-facing manager protocol and row model**

```swift
import Foundation

protocol TranscriptionModelManaging: AnyObject {
    var currentDefaultModelID: TranscriptionModelID? { get }
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
```

- [ ] **Step 4: Implement the settings view model**

```swift
import Foundation

@MainActor
final class ModelsSettingsViewModel: ObservableObject {
    @Published private(set) var rows: [TranscriptionModelRow] = []
    @Published var defaultModelID: TranscriptionModelID?
    @Published var errorMessage: String?

    private let manager: TranscriptionModelManaging

    init(manager: TranscriptionModelManaging) {
        self.manager = manager
        self.defaultModelID = manager.currentDefaultModelID
    }

    func load() async {
        let statuses = await manager.refreshStatuses()
        rows = TranscriptionModelCatalog.supportedModels.map {
            TranscriptionModelRow(id: $0.id, model: $0, state: statuses[$0.id] ?? .notInstalled)
        }
        defaultModelID = manager.currentDefaultModelID
    }

    func download(_ modelID: TranscriptionModelID) async {
        do {
            try await manager.download(modelID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    func delete(_ modelID: TranscriptionModelID) async {
        do {
            try await manager.delete(modelID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateDefaultModel(_ modelID: TranscriptionModelID?) async {
        await manager.setDefaultModelID(modelID)
        defaultModelID = manager.currentDefaultModelID
    }
}
```

- [ ] **Step 5: Add test doubles and make the tests pass**

```swift
@MainActor
private final class FakeTranscriptionModelManager: TranscriptionModelManaging {
    var currentDefaultModelID: TranscriptionModelID?
    var statuses: [TranscriptionModelID: TranscriptionModelInstallState]
    var downloadError: Error?

    init(
        statuses: [TranscriptionModelID: TranscriptionModelInstallState] = [:],
        defaultModelID: TranscriptionModelID? = nil,
        downloadError: Error? = nil
    ) {
        self.statuses = statuses
        self.currentDefaultModelID = defaultModelID
        self.downloadError = downloadError
    }

    func refreshStatuses() async -> [TranscriptionModelID: TranscriptionModelInstallState] {
        statuses
    }

    func download(_ modelID: TranscriptionModelID) async throws {
        if let downloadError { throw downloadError }
        statuses[modelID] = .installed(sizeInBytes: 1_024, installedAt: nil)
        if currentDefaultModelID == nil {
            currentDefaultModelID = modelID
        }
    }

    func delete(_ modelID: TranscriptionModelID) async throws {
        statuses[modelID] = .notInstalled
        if currentDefaultModelID == modelID {
            currentDefaultModelID = nil
        }
    }

    func setDefaultModelID(_ modelID: TranscriptionModelID?) async {
        currentDefaultModelID = modelID
    }
}
```

- [ ] **Step 6: Add the new files to the Xcode project**

```pbxproj
/* Add file references and build file entries for:
   - QuickMeeting/ViewModels/ModelsSettingsViewModel.swift
   - QuickMeetingTests/ModelsSettingsViewModelTests.swift
*/
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task-models CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/ModelsSettingsViewModelTests`

Expected: PASS for row ordering and error surfacing.

- [ ] **Step 8: Commit**

```bash
git add QuickMeeting/ViewModels/ModelsSettingsViewModel.swift \
  QuickMeetingTests/ModelsSettingsViewModelTests.swift \
  QuickMeeting.xcodeproj/project.pbxproj
git commit -m "feat: add models settings view model"
```

### Task 5: Build the Settings window and Models pane UI

**Files:**
- Create: `QuickMeeting/Views/Settings/SettingsView.swift`
- Create: `QuickMeeting/Views/Settings/ModelsSettingsView.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeeting/Services/Transcription/TranscriptionModelManager.swift`
- Modify: `QuickMeeting.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write a minimal smoke test plan for manual verification**

```text
1. Launch the app.
2. Open Settings from the app menu.
3. Verify the sidebar shows Models.
4. Verify no model download starts automatically.
5. Verify Tiny, Small, and Large v3 rows appear in that order.
```

- [ ] **Step 2: Add the Settings shell view**

```swift
import SwiftUI

struct SettingsView: View {
    @State private var selection: SettingsPane = .models
    let modelsViewModel: ModelsSettingsViewModel

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Text(pane.title)
            }
            .navigationTitle("Settings")
        } detail: {
            switch selection {
            case .models:
                ModelsSettingsView(viewModel: modelsViewModel)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case models

    var id: String { rawValue }
    var title: String { "Models" }
}
```

- [ ] **Step 3: Add the Models pane UI**

```swift
import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var viewModel: ModelsSettingsViewModel

    var body: some View {
        Form {
            Section("Default Model") {
                Picker("Model", selection: $viewModel.defaultModelID) {
                    Text("None").tag(Optional<TranscriptionModelID>.none)
                    ForEach(viewModel.rows.filter(\.isInstalled)) { row in
                        Text(row.model.displayName).tag(Optional(row.model.id))
                    }
                }
            }

            Section("Available Models") {
                ForEach(viewModel.rows) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.model.displayName)
                            Text(row.model.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.stateLabel)
                            .foregroundStyle(.secondary)
                        row.actionButton(viewModel: viewModel)
                    }
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .alert("Model Operation Failed", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
```

- [ ] **Step 4: Wire the app-level dependencies and Settings scene**

```swift
import SwiftUI
import SwiftData

@main
struct QuickMeetingApp: App {
    private let sharedModelContainer: ModelContainer
    @StateObject private var appViewModel: AppViewModel
    @StateObject private var modelsSettingsViewModel: ModelsSettingsViewModel
    @State private var menuBarController: MenuBarController?

    init() {
        let schema = Schema([Meeting.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            let transcriptionModelManager = TranscriptionModelManager(
                modelStore: ArgmaxWhisperModelStore(),
                settingsStore: ModelSettingsStore()
            )

            sharedModelContainer = modelContainer
            _appViewModel = StateObject(
                wrappedValue: AppViewModel(
                    meetingStore: MeetingStore(modelContext: modelContainer.mainContext),
                    meetingFileStore: MeetingFileStore(),
                    recordingService: DefaultRecordingService(
                        audioCapturePipeline: NativeAudioCapturePipeline()
                    )
                )
            )
            _modelsSettingsViewModel = StateObject(
                wrappedValue: ModelsSettingsViewModel(manager: transcriptionModelManager)
            )
        } catch {
            fatalError("Could not create ModelContainer: \\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appViewModel: appViewModel)
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView(modelsViewModel: modelsSettingsViewModel)
        }
    }
}
```

- [ ] **Step 5: Finish the manager protocol conformance and default-model setter**

```swift
extension TranscriptionModelManager: TranscriptionModelManaging {
    var currentDefaultModelID: TranscriptionModelID? {
        settingsStore.defaultModelID
    }

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
```

- [ ] **Step 6: Add the new files to the Xcode project**

```pbxproj
/* Add file references and build file entries for:
   - QuickMeeting/Views/Settings/SettingsView.swift
   - QuickMeeting/Views/Settings/ModelsSettingsView.swift
*/
```

- [ ] **Step 7: Run focused automated tests**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task-models CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionModelCatalogTests -only-testing:QuickMeetingTests/ModelSettingsStoreTests -only-testing:QuickMeetingTests/TranscriptionModelManagerTests -only-testing:QuickMeetingTests/ModelsSettingsViewModelTests`

Expected: PASS for all new transcription-model tests.

- [ ] **Step 8: Run manual verification in the app**

Run: `xcodebuild -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task-models CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build`

Expected: BUILD SUCCEEDED, then launch the app from Xcode and verify:

```text
- Settings opens from the app menu.
- The sidebar contains Models.
- Tiny, Small, and Large v3 appear in order.
- No download starts automatically.
- Download and delete controls render for each row.
```

- [ ] **Step 9: Commit**

```bash
git add QuickMeeting/Views/Settings/SettingsView.swift \
  QuickMeeting/Views/Settings/ModelsSettingsView.swift \
  QuickMeeting/QuickMeetingApp.swift \
  QuickMeeting/Services/Transcription/TranscriptionModelManager.swift \
  QuickMeeting.xcodeproj/project.pbxproj
git commit -m "feat: add transcription model settings UI"
```

### Task 6: Final verification and cleanup

**Files:**
- Modify: `QuickMeeting/Views/Settings/ModelsSettingsView.swift`
- Modify: `QuickMeeting/ViewModels/ModelsSettingsViewModel.swift`
- Modify: `QuickMeeting/Services/Transcription/ArgmaxWhisperModelStore.swift`

- [ ] **Step 1: Do a focused spec-to-plan coverage check**

```text
Verify the implementation covers:
- Dedicated Settings window
- Models pane only
- Fixed supported models
- Click-to-download only
- Delete installed models
- Default model selection
- Single active download
- No transcription execution
```

- [ ] **Step 2: Tighten UI details only if verification exposed gaps**

```swift
extension TranscriptionModelRow {
    var isInstalled: Bool {
        if case .installed = state { return true }
        return false
    }

    var stateLabel: String {
        switch state {
        case .notInstalled:
            return "Not Installed"
        case .downloading:
            return "Downloading"
        case .installed(let sizeInBytes, _):
            return ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
        case .failed:
            return "Failed"
        }
    }
}
```

- [ ] **Step 3: Run the full relevant test suite**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task-models CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionModelCatalogTests -only-testing:QuickMeetingTests/ModelSettingsStoreTests -only-testing:QuickMeetingTests/TranscriptionModelManagerTests -only-testing:QuickMeetingTests/ModelsSettingsViewModelTests -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/MeetingFileStoreTests`

Expected: PASS with no regressions in existing meeting and recording tests.

- [ ] **Step 4: Commit the cleanup if any files changed**

```bash
git add QuickMeeting/Views/Settings/ModelsSettingsView.swift \
  QuickMeeting/ViewModels/ModelsSettingsViewModel.swift \
  QuickMeeting/Services/Transcription/ArgmaxWhisperModelStore.swift
git commit -m "chore: polish transcription model management"
```
