**Goal:** Replace the single hardcoded auto-recording app with a user-managed watched-app list selected from Finder, while keeping the detection and auto-start/stop logic generic.

**Architecture:** Migrate auto-recording settings from one enum-backed app choice to a lightweight persisted `AutoRecordingTarget` list keyed by bundle identifier. Add a small metadata-reading boundary for `.app` selection, update the Settings UI and view model to add/remove watched apps with validation and deduplication, then update the activity source and monitor to evaluate “any watched app qualifies” without introducing per-app behavior.

**Tech Stack:** Swift, SwiftUI, AppKit, Foundation, UniformTypeIdentifiers, SwiftData, Testing

---

## File Structure

**Create:**
- `QuickMeeting/Services/AutoRecording/AppBundleMetadata.swift`
- `QuickMeeting/Services/AutoRecording/AppBundleMetadataReader.swift`

**Modify:**
- `QuickMeeting/Models/AutoRecordingSettings.swift`
- `QuickMeeting/Services/AutoRecording/AutoRecordingSettingsStore.swift`
- `QuickMeeting/Services/AutoRecording/MeetingAppActivitySource.swift`
- `QuickMeeting/Services/AutoRecording/NativeMeetingAppActivitySource.swift`
- `QuickMeeting/Services/AutoRecording/MeetingAppMonitor.swift`
- `QuickMeeting/ViewModels/AutoRecordingSettingsViewModel.swift`
- `QuickMeeting/Views/Settings/AutoRecordingSettingsSections.swift`
- `QuickMeeting/ViewModels/AppViewModel.swift`
- `QuickMeeting/QuickMeetingApp.swift`
- `QuickMeetingTests/AutoRecordingSettingsStoreTests.swift`
- `QuickMeetingTests/AutoRecordingSettingsViewModelTests.swift`
- `QuickMeetingTests/NativeMeetingAppActivitySourceTests.swift`
- `QuickMeetingTests/AppViewModelTests.swift`

**Why these files:**
- `AutoRecordingSettings.swift` and `AutoRecordingSettingsStore.swift` are where the single-app assumption currently lives.
- `AppBundleMetadata.swift` and `AppBundleMetadataReader.swift` isolate Finder-selected `.app` validation and metadata extraction so the view model stays testable.
- `MeetingAppActivitySource.swift`, `NativeMeetingAppActivitySource.swift`, and `MeetingAppMonitor.swift` are the runtime boundary for switching from one selected app to “any watched bundle ID qualifies.”
- `AutoRecordingSettingsViewModel.swift` and `AutoRecordingSettingsSections.swift` match the existing Settings decomposition and keep import/remove logic out of the top-level form.
- `AppViewModel.swift` and `QuickMeetingApp.swift` are the only integration points that need user-visible text and dependency wiring updates.

### Task 1: Migrate settings persistence from one app to a watched-app list

**Files:**
- Modify: `QuickMeeting/Models/AutoRecordingSettings.swift`
- Modify: `QuickMeeting/Services/AutoRecording/AutoRecordingSettingsStore.swift`
- Test: `QuickMeetingTests/AutoRecordingSettingsStoreTests.swift`

- [ ] **Step 1: Write the failing settings migration and round-trip tests**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct AutoRecordingSettingsStoreTests {
    @Test
    func settingsRoundTripWithMultipleTargets() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = AutoRecordingSettingsStore(userDefaults: defaults)

        #expect(store.load().isEnabled == false)
        #expect(store.load().selectedApps.isEmpty)
        #expect(store.load().startDelay == 10)
        #expect(store.load().stopGracePeriod == 60)

        let updated = AutoRecordingSettings(
            isEnabled: true,
            selectedApps: [
                AutoRecordingTarget(
                    bundleIdentifier: "us.zoom.xos",
                    displayName: "zoom.us",
                    appPath: "/Applications/zoom.us.app"
                ),
                AutoRecordingTarget(
                    bundleIdentifier: "com.microsoft.teams2",
                    displayName: "Microsoft Teams",
                    appPath: "/Applications/Microsoft Teams.app"
                )
            ],
            startDelay: 12,
            stopGracePeriod: 75
        )
        store.save(updated)

        #expect(store.load() == updated)
    }

    @Test
    func legacySelectedAppMigratesToWatchedList() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("tolk", forKey: "autoRecording.app")
        let store = AutoRecordingSettingsStore(userDefaults: defaults)

        let migrated = store.load()
        #expect(migrated.selectedApps == [
            AutoRecordingTarget(
                bundleIdentifier: "kontur.talk",
                displayName: "Толк",
                appPath: ""
            )
        ])
    }
}
```

- [ ] **Step 2: Run the focused store test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsStoreTests`

Expected: FAIL because `selectedApps` and `AutoRecordingTarget` do not exist yet.

- [ ] **Step 3: Replace the single-app model with a watched-target model**

```swift
import Foundation

struct AutoRecordingTarget: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let appPath: String

    static let legacyTolk = AutoRecordingTarget(
        bundleIdentifier: "kontur.talk",
        displayName: "Толк",
        appPath: ""
    )
}

struct AutoRecordingSettings: Equatable, Sendable {
    var isEnabled: Bool
    var selectedApps: [AutoRecordingTarget]
    var startDelay: TimeInterval
    var stopGracePeriod: TimeInterval

    static let `default` = AutoRecordingSettings(
        isEnabled: false,
        selectedApps: [],
        startDelay: 10,
        stopGracePeriod: 60
    )
}
```

- [ ] **Step 4: Update the store to save the watched list and migrate legacy data**

```swift
import Foundation

protocol AutoRecordingSettingsStoring: Sendable {
    func load() -> AutoRecordingSettings
    func save(_ settings: AutoRecordingSettings)
}

struct AutoRecordingSettingsStore: AutoRecordingSettingsStoring {
    private let userDefaults: UserDefaults
    private let enabledKey = "autoRecording.enabled"
    private let appsKey = "autoRecording.apps"
    private let legacyAppKey = "autoRecording.app"
    private let startDelayKey = "autoRecording.startDelay"
    private let stopGraceKey = "autoRecording.stopGrace"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AutoRecordingSettings {
        let defaults = AutoRecordingSettings.default
        let selectedApps = loadSelectedApps()

        return AutoRecordingSettings(
            isEnabled: userDefaults.object(forKey: enabledKey) as? Bool ?? defaults.isEnabled,
            selectedApps: selectedApps,
            startDelay: userDefaults.object(forKey: startDelayKey) as? Double ?? defaults.startDelay,
            stopGracePeriod: userDefaults.object(forKey: stopGraceKey) as? Double ?? defaults.stopGracePeriod
        )
    }

    func save(_ settings: AutoRecordingSettings) {
        userDefaults.set(settings.isEnabled, forKey: enabledKey)
        userDefaults.set(encode(uniqueTargets(from: settings.selectedApps)), forKey: appsKey)
        userDefaults.removeObject(forKey: legacyAppKey)
        userDefaults.set(settings.startDelay, forKey: startDelayKey)
        userDefaults.set(settings.stopGracePeriod, forKey: stopGraceKey)
    }

    private func loadSelectedApps() -> [AutoRecordingTarget] {
        if let data = userDefaults.data(forKey: appsKey),
           let decoded = try? JSONDecoder().decode([AutoRecordingTarget].self, from: data) {
            return uniqueTargets(from: decoded)
        }

        guard let legacy = userDefaults.string(forKey: legacyAppKey), legacy == "tolk" else {
            return []
        }

        return [.legacyTolk]
    }

    private func uniqueTargets(from targets: [AutoRecordingTarget]) -> [AutoRecordingTarget] {
        var seen = Set<String>()
        return targets.filter { seen.insert($0.bundleIdentifier).inserted }
    }

    private func encode(_ targets: [AutoRecordingTarget]) -> Data? {
        try? JSONEncoder().encode(targets)
    }
}
```

- [ ] **Step 5: Re-run the store tests and verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsStoreTests`

Expected: PASS for the multi-target round-trip and legacy migration tests.

- [ ] **Step 6: Commit the settings migration**

```bash
git add QuickMeeting/Models/AutoRecordingSettings.swift QuickMeeting/Services/AutoRecording/AutoRecordingSettingsStore.swift QuickMeetingTests/AutoRecordingSettingsStoreTests.swift
git commit -m "feat: migrate auto recording settings to watched apps"
```

### Task 2: Add a testable app-bundle metadata reader and watched-app view-model actions

**Files:**
- Create: `QuickMeeting/Services/AutoRecording/AppBundleMetadata.swift`
- Create: `QuickMeeting/Services/AutoRecording/AppBundleMetadataReader.swift`
- Modify: `QuickMeeting/ViewModels/AutoRecordingSettingsViewModel.swift`
- Test: `QuickMeetingTests/AutoRecordingSettingsViewModelTests.swift`

- [ ] **Step 1: Write the failing view-model tests for add, dedupe, invalid selection, and remove**

```swift
import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct AutoRecordingSettingsViewModelTests {
    @Test
    func addSelectedAppPersistsNewWatchedTarget() async throws {
        let store = InMemoryAutoRecordingSettingsStore(settings: .default)
        let reader = StubAppBundleMetadataReader(
            result: .success(
                AppBundleMetadata(
                    bundleIdentifier: "us.zoom.xos",
                    displayName: "zoom.us",
                    appPath: "/Applications/zoom.us.app"
                )
            )
        )
        let viewModel = AutoRecordingSettingsViewModel(
            settingsStore: store,
            metadataReader: reader
        )

        try await viewModel.addSelectedApp(at: URL(fileURLWithPath: "/Applications/zoom.us.app"))

        #expect(store.settings.selectedApps == [
            AutoRecordingTarget(
                bundleIdentifier: "us.zoom.xos",
                displayName: "zoom.us",
                appPath: "/Applications/zoom.us.app"
            )
        ])
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func addSelectedAppIgnoresDuplicateBundleIdentifier() async throws {
        let existing = AutoRecordingTarget(
            bundleIdentifier: "us.zoom.xos",
            displayName: "zoom.us",
            appPath: "/Applications/zoom.us.app"
        )
        let store = InMemoryAutoRecordingSettingsStore(
            settings: AutoRecordingSettings(
                isEnabled: true,
                selectedApps: [existing],
                startDelay: 10,
                stopGracePeriod: 60
            )
        )
        let reader = StubAppBundleMetadataReader(
            result: .success(
                AppBundleMetadata(
                    bundleIdentifier: "us.zoom.xos",
                    displayName: "Zoom Clone",
                    appPath: "/Applications/Zoom Clone.app"
                )
            )
        )
        let viewModel = AutoRecordingSettingsViewModel(
            settingsStore: store,
            metadataReader: reader
        )

        try await viewModel.addSelectedApp(at: URL(fileURLWithPath: "/Applications/Zoom Clone.app"))

        #expect(store.settings.selectedApps == [existing])
    }

    @Test
    func addSelectedAppStoresValidationError() async {
        let store = InMemoryAutoRecordingSettingsStore(settings: .default)
        let reader = StubAppBundleMetadataReader(
            result: .failure(.missingBundleIdentifier)
        )
        let viewModel = AutoRecordingSettingsViewModel(
            settingsStore: store,
            metadataReader: reader
        )

        await #expect(throws: Never.self) {
            try await viewModel.addSelectedApp(at: URL(fileURLWithPath: "/Applications/Broken.app"))
        }

        #expect(viewModel.errorMessage == "Selected app has no bundle identifier.")
        #expect(store.settings.selectedApps.isEmpty)
    }

    @Test
    func removeSelectedAppPersistsUpdatedWatchedList() async {
        let zoom = AutoRecordingTarget(
            bundleIdentifier: "us.zoom.xos",
            displayName: "zoom.us",
            appPath: "/Applications/zoom.us.app"
        )
        let teams = AutoRecordingTarget(
            bundleIdentifier: "com.microsoft.teams2",
            displayName: "Microsoft Teams",
            appPath: "/Applications/Microsoft Teams.app"
        )
        let store = InMemoryAutoRecordingSettingsStore(
            settings: AutoRecordingSettings(
                isEnabled: true,
                selectedApps: [zoom, teams],
                startDelay: 10,
                stopGracePeriod: 60
            )
        )
        let viewModel = AutoRecordingSettingsViewModel(settingsStore: store)

        await viewModel.load()
        await viewModel.removeSelectedApp(bundleIdentifier: "us.zoom.xos")

        #expect(store.settings.selectedApps == [teams])
    }
}
```

- [ ] **Step 2: Run the focused view-model tests and verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsViewModelTests`

Expected: FAIL because the metadata reader, watched list, and add/remove APIs do not exist yet.

- [ ] **Step 3: Add metadata types and a native bundle reader**

```swift
import Foundation

struct AppBundleMetadata: Equatable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let appPath: String
}
```

```swift
import Foundation

enum AppBundleMetadataReaderError: LocalizedError, Equatable {
    case invalidApplication
    case missingBundleIdentifier
    case unreadableMetadata

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            return "Selected item is not a valid application."
        case .missingBundleIdentifier:
            return "Selected app has no bundle identifier."
        case .unreadableMetadata:
            return "Couldn't read app metadata."
        }
    }
}

protocol AppBundleMetadataReading: Sendable {
    func readMetadata(at url: URL) throws -> AppBundleMetadata
}

struct NativeAppBundleMetadataReader: AppBundleMetadataReading {
    func readMetadata(at url: URL) throws -> AppBundleMetadata {
        guard url.pathExtension == "app",
              let bundle = Bundle(url: url) else {
            throw AppBundleMetadataReaderError.invalidApplication
        }
        guard let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            throw AppBundleMetadataReaderError.missingBundleIdentifier
        }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        return AppBundleMetadata(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            appPath: url.path
        )
    }
}
```

- [ ] **Step 4: Update the view model to manage watched apps and error state**

```swift
import Combine
import Foundation

@MainActor
final class AutoRecordingSettingsViewModel: ObservableObject {
    @Published var isEnabled = false
    @Published var selectedApps: [AutoRecordingTarget] = []
    @Published var startDelay: Double = 10
    @Published var stopGracePeriod: Double = 60
    @Published private(set) var errorMessage: String?

    private let settingsStore: any AutoRecordingSettingsStoring
    private let metadataReader: any AppBundleMetadataReading

    init(
        settingsStore: any AutoRecordingSettingsStoring,
        metadataReader: any AppBundleMetadataReading = NativeAppBundleMetadataReader()
    ) {
        self.settingsStore = settingsStore
        self.metadataReader = metadataReader
    }

    func load() async {
        let settings = settingsStore.load()
        isEnabled = settings.isEnabled
        selectedApps = settings.selectedApps
        startDelay = settings.startDelay
        stopGracePeriod = settings.stopGracePeriod
        errorMessage = nil
    }

    func save() async {
        settingsStore.save(
            AutoRecordingSettings(
                isEnabled: isEnabled,
                selectedApps: selectedApps,
                startDelay: startDelay,
                stopGracePeriod: stopGracePeriod
            )
        )
    }

    func addSelectedApp(at url: URL) async throws {
        do {
            let metadata = try metadataReader.readMetadata(at: url)
            guard !selectedApps.contains(where: { $0.bundleIdentifier == metadata.bundleIdentifier }) else {
                errorMessage = nil
                return
            }

            selectedApps.append(
                AutoRecordingTarget(
                    bundleIdentifier: metadata.bundleIdentifier,
                    displayName: metadata.displayName,
                    appPath: metadata.appPath
                )
            )
            errorMessage = nil
            await save()
        } catch let error as AppBundleMetadataReaderError {
            errorMessage = error.localizedDescription
        }
    }

    func removeSelectedApp(bundleIdentifier: String) async {
        selectedApps.removeAll { $0.bundleIdentifier == bundleIdentifier }
        errorMessage = nil
        await save()
    }

    func clearError() {
        errorMessage = nil
    }
}
```

- [ ] **Step 5: Re-run the view-model tests and verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsViewModelTests`

Expected: PASS for add, dedupe, invalid selection, and remove behaviors.

- [ ] **Step 6: Commit the metadata and view-model slice**

```bash
git add QuickMeeting/Services/AutoRecording/AppBundleMetadata.swift QuickMeeting/Services/AutoRecording/AppBundleMetadataReader.swift QuickMeeting/ViewModels/AutoRecordingSettingsViewModel.swift QuickMeetingTests/AutoRecordingSettingsViewModelTests.swift
git commit -m "feat: manage watched apps in auto recording settings"
```

### Task 3: Replace the single-app picker with Finder import and inline removal

**Files:**
- Modify: `QuickMeeting/Views/Settings/AutoRecordingSettingsSections.swift`

- [ ] **Step 1: Add the failing UI-facing behavior test in the view-model suite**

```swift
@Test
func loadExposesPersistedWatchedAppsForSettingsList() async {
    let zoom = AutoRecordingTarget(
        bundleIdentifier: "us.zoom.xos",
        displayName: "zoom.us",
        appPath: "/Applications/zoom.us.app"
    )
    let store = InMemoryAutoRecordingSettingsStore(
        settings: AutoRecordingSettings(
            isEnabled: true,
            selectedApps: [zoom],
            startDelay: 10,
            stopGracePeriod: 60
        )
    )
    let viewModel = AutoRecordingSettingsViewModel(settingsStore: store)

    await viewModel.load()

    #expect(viewModel.selectedApps == [zoom])
}
```

- [ ] **Step 2: Re-run the focused view-model test to keep the UI contract green**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsViewModelTests/loadExposesPersistedWatchedAppsForSettingsList`

Expected: PASS, confirming the UI can bind to the watched-app list before the view changes.

- [ ] **Step 3: Replace the picker with a file importer, watched list, helper text, and remove actions**

```swift
import SwiftUI
import UniformTypeIdentifiers

struct AutoRecordingSettingsSections: View {
    @ObservedObject var viewModel: AutoRecordingSettingsViewModel
    @State private var isImporterPresented = false

    var body: some View {
        Section("Auto Recording") {
            Toggle("Enable auto recording", isOn: $viewModel.isEnabled)

            Button("Add App...") {
                isImporterPresented = true
            }

            if viewModel.selectedApps.isEmpty {
                Text("No apps selected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.selectedApps, id: \.bundleIdentifier) { app in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName)
                            Text(app.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            Task { await viewModel.removeSelectedApp(bundleIdentifier: app.bundleIdentifier) }
                        }
                    }
                }
            }

            Text("Recording starts when the microphone is active and any selected app is in use.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Start delay")
                Spacer()
                Text("\(Int(viewModel.startDelay))s")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $viewModel.startDelay, in: 5 ... 20, step: 1)

            HStack {
                Text("Stop grace period")
                Spacer()
                Text("\(Int(viewModel.stopGracePeriod))s")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $viewModel.stopGracePeriod, in: 30 ... 120, step: 5)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.application],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                return
            }

            Task { try await viewModel.addSelectedApp(at: url) }
        }
        .onChange(of: viewModel.isEnabled) { _, _ in
            Task { await viewModel.save() }
        }
        .onChange(of: viewModel.startDelay) { _, _ in
            Task { await viewModel.save() }
        }
        .onChange(of: viewModel.stopGracePeriod) { _, _ in
            Task { await viewModel.save() }
        }
    }
}
```

- [ ] **Step 4: Surface settings errors from the new view-model state**

```swift
.alert("Auto Recording App Error", isPresented: autoRecordingErrorIsPresented) {
    Button("OK") {
        autoRecordingViewModel.clearError()
    }
} message: {
    Text(autoRecordingViewModel.errorMessage ?? "Unknown error.")
}
```

```swift
private var autoRecordingErrorIsPresented: Binding<Bool> {
    Binding(
        get: { autoRecordingViewModel.errorMessage != nil },
        set: { isPresented in
            if !isPresented {
                autoRecordingViewModel.clearError()
            }
        }
    )
}
```

- [ ] **Step 5: Run the watched-app settings tests again**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsViewModelTests`

Expected: PASS, with no regressions after the SwiftUI wiring.

- [ ] **Step 6: Commit the settings UI update**

```bash
git add QuickMeeting/Views/Settings/AutoRecordingSettingsSections.swift QuickMeeting/Views/Settings/SettingsView.swift
git commit -m "feat: add watched app picker to auto recording settings"
```

### Task 4: Update the runtime to evaluate any watched app without app-specific logic

**Files:**
- Modify: `QuickMeeting/Services/AutoRecording/MeetingAppActivitySource.swift`
- Modify: `QuickMeeting/Services/AutoRecording/NativeMeetingAppActivitySource.swift`
- Modify: `QuickMeeting/Services/AutoRecording/MeetingAppMonitor.swift`
- Test: `QuickMeetingTests/NativeMeetingAppActivitySourceTests.swift`

- [ ] **Step 1: Add failing tests for bundle-ID sampling and any-app monitoring**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct NativeMeetingAppActivitySourceTests {
    @Test
    func sampleUsesProvidedBundleIdentifier() {
        let source = NativeMeetingAppActivitySource(
            runningBundleIdentifiers: { ["us.zoom.xos"] },
            frontmostBundleIdentifier: { "us.zoom.xos" },
            visibleWindowBundleIdentifiers: { ["us.zoom.xos"] },
            microphoneActivitySource: StubMicrophoneActivitySource(isActive: true)
        )

        let sample = source.sample(forBundleIdentifier: "us.zoom.xos")
        #expect(sample.bundleIdentifier == "us.zoom.xos")
        #expect(sample.isRunning == true)
        #expect(sample.hasVisibleWindow == true)
    }
}
```

```swift
@MainActor
struct MeetingAppMonitorTests {
    @Test
    func anyWatchedAppCanDrivePresenceActive() async {
        let settingsStore = InMemoryAutoRecordingSettingsStore(
            settings: AutoRecordingSettings(
                isEnabled: true,
                selectedApps: [
                    AutoRecordingTarget(
                        bundleIdentifier: "us.zoom.xos",
                        displayName: "zoom.us",
                        appPath: "/Applications/zoom.us.app"
                    ),
                    AutoRecordingTarget(
                        bundleIdentifier: "com.microsoft.teams2",
                        displayName: "Microsoft Teams",
                        appPath: "/Applications/Microsoft Teams.app"
                    )
                ],
                startDelay: 10,
                stopGracePeriod: 60
            )
        )
        let activitySource = StubMeetingAppActivitySource(samplesByBundleIdentifier: [
            "us.zoom.xos": MeetingAppActivitySample(
                bundleIdentifier: "us.zoom.xos",
                isRunning: false,
                isFrontmost: false,
                hadRecentFocus: false,
                hasVisibleWindow: false,
                isMicrophoneActive: false
            ),
            "com.microsoft.teams2": MeetingAppActivitySample(
                bundleIdentifier: "com.microsoft.teams2",
                isRunning: true,
                isFrontmost: false,
                hadRecentFocus: true,
                hasVisibleWindow: false,
                isMicrophoneActive: true
            )
        ])
        let viewModel = AppViewModel.makeAutoRecordingTestDouble()
        let monitor = MeetingAppMonitor(
            settingsStore: settingsStore,
            activitySource: activitySource,
            appViewModel: viewModel
        )

        await monitor.pollOnceForTesting()

        #expect(viewModel.lastAutoRecordingPresence == .candidateActive)
    }
}
```

- [ ] **Step 2: Run the targeted runtime tests and verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeMeetingAppActivitySourceTests`

Expected: FAIL because the source still samples by enum.

- [ ] **Step 3: Change the activity-source boundary from enum-based sampling to bundle-ID sampling**

```swift
import Foundation

protocol MeetingAppActivitySource: Sendable {
    func sample(forBundleIdentifier bundleIdentifier: String) -> MeetingAppActivitySample
}
```

```swift
import AppKit
import Foundation

final class NativeMeetingAppActivitySource: MeetingAppActivitySource, @unchecked Sendable {
    // existing properties stay the same

    func sample(forBundleIdentifier bundleIdentifier: String) -> MeetingAppActivitySample {
        if let frontmostBundleIdentifier = frontmostBundleIdentifier() {
            lastFocusedAtByBundleIdentifier[frontmostBundleIdentifier] = now()
        }

        let isFrontmost = frontmostBundleIdentifier() == bundleIdentifier
        let hadRecentFocus = lastFocusedAtByBundleIdentifier[bundleIdentifier].map {
            now().timeIntervalSince($0) <= recentFocusWindow
        } ?? false

        return MeetingAppActivitySample(
            bundleIdentifier: bundleIdentifier,
            isRunning: runningBundleIdentifiers().contains(bundleIdentifier),
            isFrontmost: isFrontmost,
            hadRecentFocus: hadRecentFocus,
            hasVisibleWindow: visibleWindowBundleIdentifiers().contains(bundleIdentifier),
            isMicrophoneActive: microphoneActivitySource.isMicrophoneActive()
        )
    }
}
```

- [ ] **Step 4: Update the monitor to aggregate “any watched app qualifies”**

```swift
@MainActor
final class MeetingAppMonitor {
    // existing properties stay the same
    private var lastSelectedBundleIdentifiers: [String] = []

    func pollOnceForTesting() async {
        await pollOnce()
    }

    private func pollOnce() async {
        let settings = settingsStore.load()

        guard settings.isEnabled else {
            detector = MeetingPresenceDetector()
            lastSelectedBundleIdentifiers = []
            await appViewModel.updateAutoRecordingPresence(.inactive)
            return
        }

        let bundleIdentifiers = settings.selectedApps.map(\.bundleIdentifier)
        guard !bundleIdentifiers.isEmpty else {
            detector = MeetingPresenceDetector()
            lastSelectedBundleIdentifiers = []
            await appViewModel.updateAutoRecordingPresence(.inactive)
            return
        }

        if lastSelectedBundleIdentifiers != bundleIdentifiers {
            detector = MeetingPresenceDetector()
            lastSelectedBundleIdentifiers = bundleIdentifiers
        }

        let samples = bundleIdentifiers.map { activitySource.sample(forBundleIdentifier: $0) }
        if let qualifyingSample = samples.first(where: {
            $0.isMicrophoneActive && $0.isRunning && ($0.hasVisibleWindow || $0.hadRecentFocus)
        }) {
            await appViewModel.updateAutoRecordingPresence(detector.evaluate(qualifyingSample))
            return
        }

        let fallback = samples.first ?? MeetingAppActivitySample(
            bundleIdentifier: bundleIdentifiers[0],
            isRunning: false,
            isFrontmost: false,
            hadRecentFocus: false,
            hasVisibleWindow: false,
            isMicrophoneActive: false
        )
        let detectedPresence = detector.evaluate(fallback)
        let presentationPresence = detectedPresence == .inactive && appViewModel.canStopRecording
            ? .ending
            : detectedPresence
        await appViewModel.updateAutoRecordingPresence(presentationPresence)
    }
}
```

- [ ] **Step 5: Re-run the targeted runtime tests and verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeMeetingAppActivitySourceTests -only-testing:QuickMeetingTests/AutoRecordingSettingsStoreTests`

Expected: PASS for the bundle-ID sampling and watched-list store behavior.

- [ ] **Step 6: Commit the runtime aggregation update**

```bash
git add QuickMeeting/Services/AutoRecording/MeetingAppActivitySource.swift QuickMeeting/Services/AutoRecording/NativeMeetingAppActivitySource.swift QuickMeeting/Services/AutoRecording/MeetingAppMonitor.swift QuickMeetingTests/NativeMeetingAppActivitySourceTests.swift
git commit -m "feat: monitor multiple apps for auto recording"
```

### Task 5: Finish app wiring and update user-visible status text

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing status-text regression test**

```swift
@Test
func autoRecordingPresenceUpdatesStatusTextWithoutAppSpecificName() async throws {
    let harness = try AppViewModelTestHarness()
    let viewModel = AppViewModel(
        meetingStore: harness.meetingStore,
        meetingFileStore: harness.meetingFileStore,
        recordingService: harness.recordingService,
        recordingPermissions: harness.recordingPermissions
    )

    await viewModel.updateAutoRecordingPresence(.candidateActive)
    #expect(viewModel.autoRecordingStatusText == "Detected meeting activity, waiting 10s")

    await viewModel.updateAutoRecordingPresence(.ending)
    #expect(viewModel.autoRecordingStatusText == "Meeting activity lost, stopping soon")

    await viewModel.updateAutoRecordingPresence(.inactive)
    #expect(viewModel.autoRecordingStatusText == nil)
}
```

- [ ] **Step 2: Run the focused app-view-model test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests/autoRecordingPresenceUpdatesStatusTextWithoutAppSpecificName`

Expected: FAIL because the current text still hardcodes `Толк`.

- [ ] **Step 3: Remove the app-specific status copy and wire the new reader into app startup**

```swift
func updateAutoRecordingPresence(_ presence: MeetingAppPresence) async {
    switch presence {
    case .candidateActive, .activeMeeting:
        autoRecordingStatusText = "Detected meeting activity, waiting 10s"
    case .ending:
        autoRecordingStatusText = "Meeting activity lost, stopping soon"
    case .inactive:
        autoRecordingStatusText = nil
    }

    await autoRecordingCoordinator?.handle(presence)
}
```

```swift
let autoRecordingSettingsViewModel = AutoRecordingSettingsViewModel(
    settingsStore: autoRecordingSettingsStore,
    metadataReader: NativeAppBundleMetadataReader()
)
```

- [ ] **Step 4: Re-run the focused regression tests**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/AutoRecordingSettingsViewModelTests -only-testing:QuickMeetingTests/AutoRecordingSettingsStoreTests -only-testing:QuickMeetingTests/NativeMeetingAppActivitySourceTests`

Expected: PASS for the updated auto-recording settings, runtime, and status-text suites.

- [ ] **Step 5: Commit the final integration**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: support multi-app auto recording"
```

## Self-Review

- Spec coverage: this plan covers persisted watched-app records, Finder-based app selection, bundle-ID validation, deduplication, removal, empty-list behavior, migration from legacy `Толк`, any-app runtime aggregation, and generic status copy.
- Placeholder scan: no `TBD`, `TODO`, “handle appropriately,” or cross-task “same as above” gaps remain.
- Type consistency: the plan consistently uses `AutoRecordingTarget`, `selectedApps`, `AppBundleMetadata`, `AppBundleMetadataReading.readMetadata(at:)`, `addSelectedApp(at:)`, `removeSelectedApp(bundleIdentifier:)`, and `sample(forBundleIdentifier:)`.

Offer: once you want to move, the next step is to execute this plan task by task.
