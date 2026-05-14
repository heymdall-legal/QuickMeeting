**Goal:** Add an auto-recording mode that detects likely live meetings in the native `Толк` macOS app, starts recording after 10 seconds of stable activity, and stops after 60 seconds without qualifying activity.

**Architecture:** Add a small auto-recording slice around the existing recording flow: app-owned settings and presence models, a native app-activity source for `Толк`, a detector that translates sampled OS activity into stable presence states, and a coordinator that applies start and stop timing before calling the existing `AppViewModel` recording paths. Keep `RecordingService` unchanged and make auto-recording optional, visible, and testable through protocol-backed dependencies.

**Tech Stack:** Swift, SwiftUI, AppKit, Foundation, Combine, SwiftData, Testing

---

## File Structure

**Create:**
- `QuickMeeting/Models/AutoRecordingSettings.swift`
- `QuickMeeting/Models/MeetingAppPresence.swift`
- `QuickMeeting/Services/AutoRecording/AutoRecordingSettingsStore.swift`
- `QuickMeeting/Services/AutoRecording/MeetingAppActivitySource.swift`
- `QuickMeeting/Services/AutoRecording/NativeMeetingAppActivitySource.swift`
- `QuickMeeting/Services/AutoRecording/MeetingPresenceDetector.swift`
- `QuickMeeting/Services/AutoRecording/AutoRecordingCoordinator.swift`
- `QuickMeeting/ViewModels/AutoRecordingSettingsViewModel.swift`
- `QuickMeeting/Views/Settings/AutoRecordingSettingsSections.swift`
- `QuickMeetingTests/AutoRecordingSettingsStoreTests.swift`
- `QuickMeetingTests/MeetingPresenceDetectorTests.swift`
- `QuickMeetingTests/AutoRecordingCoordinatorTests.swift`
- `QuickMeetingTests/AutoRecordingSettingsViewModelTests.swift`

**Modify:**
- `QuickMeeting/ViewModels/AppViewModel.swift`
- `QuickMeeting/Views/HomeView.swift`
- `QuickMeeting/MenuBar/MenuBarView.swift`
- `QuickMeeting/Views/Settings/SettingsView.swift`
- `QuickMeeting/QuickMeetingApp.swift`
- `QuickMeetingTests/AppViewModelTests.swift`
- `docs/quickmeeting-architecture-design.md`

**Why these files:**
- `AutoRecordingSettings.swift` and `MeetingAppPresence.swift` keep auto-recording state app-owned instead of leaking raw OS details into the UI.
- `AutoRecordingSettingsStore.swift`, `MeetingAppActivitySource.swift`, and `NativeMeetingAppActivitySource.swift` isolate persistence and native app inspection from view models.
- `MeetingPresenceDetector.swift` and `AutoRecordingCoordinator.swift` keep heuristic evaluation and timing rules separate so they can be tested independently.
- `AutoRecordingSettingsViewModel.swift` and `AutoRecordingSettingsSections.swift` match the existing Settings pattern without bloating `SettingsView.swift`.
- `AppViewModel.swift`, `HomeView.swift`, `MenuBarView.swift`, and `QuickMeetingApp.swift` are the integration points for surfacing status and wiring the feature into the app shell.

### Task 1: Add app-owned auto-recording settings and persistence

**Files:**
- Create: `QuickMeeting/Models/AutoRecordingSettings.swift`
- Create: `QuickMeeting/Services/AutoRecording/AutoRecordingSettingsStore.swift`
- Create: `QuickMeetingTests/AutoRecordingSettingsStoreTests.swift`

- [ ] **Step 1: Write the failing settings-store test**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct AutoRecordingSettingsStoreTests {
    @Test
    func settingsRoundTripWithDefaults() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = AutoRecordingSettingsStore(userDefaults: defaults)

        #expect(store.load().isEnabled == false)
        #expect(store.load().selectedApp == .tolk)
        #expect(store.load().startDelay == 10)
        #expect(store.load().stopGracePeriod == 60)

        let updated = AutoRecordingSettings(
            isEnabled: true,
            selectedApp: .tolk,
            startDelay: 12,
            stopGracePeriod: 75
        )
        store.save(updated)

        #expect(store.load() == updated)
    }
}
```

- [ ] **Step 2: Run the targeted test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsStoreTests`

Expected: FAIL with missing `AutoRecordingSettingsStore` or missing `AutoRecordingSettings`.

- [ ] **Step 3: Add the app-owned settings model**

```swift
import Foundation

enum AutoRecordingApp: String, CaseIterable, Codable, Equatable, Sendable {
    case tolk

    var displayName: String {
        switch self {
        case .tolk:
            return "Толк"
        }
    }
}

struct AutoRecordingSettings: Equatable, Sendable {
    var isEnabled: Bool
    var selectedApp: AutoRecordingApp
    var startDelay: TimeInterval
    var stopGracePeriod: TimeInterval

    static let `default` = AutoRecordingSettings(
        isEnabled: false,
        selectedApp: .tolk,
        startDelay: 10,
        stopGracePeriod: 60
    )
}
```

- [ ] **Step 4: Add the lightweight settings store**

```swift
import Foundation

protocol AutoRecordingSettingsStoring: Sendable {
    func load() -> AutoRecordingSettings
    func save(_ settings: AutoRecordingSettings)
}

struct AutoRecordingSettingsStore: AutoRecordingSettingsStoring {
    private let userDefaults: UserDefaults
    private let enabledKey = "autoRecording.enabled"
    private let appKey = "autoRecording.app"
    private let startDelayKey = "autoRecording.startDelay"
    private let stopGraceKey = "autoRecording.stopGrace"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AutoRecordingSettings {
        let base = AutoRecordingSettings.default
        let selectedApp = AutoRecordingApp(
            rawValue: userDefaults.string(forKey: appKey) ?? ""
        ) ?? base.selectedApp

        return AutoRecordingSettings(
            isEnabled: userDefaults.object(forKey: enabledKey) as? Bool ?? base.isEnabled,
            selectedApp: selectedApp,
            startDelay: userDefaults.object(forKey: startDelayKey) as? Double ?? base.startDelay,
            stopGracePeriod: userDefaults.object(forKey: stopGraceKey) as? Double ?? base.stopGracePeriod
        )
    }

    func save(_ settings: AutoRecordingSettings) {
        userDefaults.set(settings.isEnabled, forKey: enabledKey)
        userDefaults.set(settings.selectedApp.rawValue, forKey: appKey)
        userDefaults.set(settings.startDelay, forKey: startDelayKey)
        userDefaults.set(settings.stopGracePeriod, forKey: stopGraceKey)
    }
}
```

- [ ] **Step 5: Re-run the targeted test and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsStoreTests`

Expected: PASS for the new round-trip test.

- [ ] **Step 6: Commit the settings slice**

```bash
git add QuickMeeting/Models/AutoRecordingSettings.swift QuickMeeting/Services/AutoRecording/AutoRecordingSettingsStore.swift QuickMeetingTests/AutoRecordingSettingsStoreTests.swift
git commit -m "feat: add auto recording settings store"
```

### Task 2: Add native `Толк` activity sampling and presence models

**Files:**
- Create: `QuickMeeting/Models/MeetingAppPresence.swift`
- Create: `QuickMeeting/Services/AutoRecording/MeetingAppActivitySource.swift`
- Create: `QuickMeeting/Services/AutoRecording/NativeMeetingAppActivitySource.swift`
- Create: `QuickMeetingTests/MeetingPresenceDetectorTests.swift`

- [ ] **Step 1: Write the failing detector test for stable activation**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct MeetingPresenceDetectorTests {
    @Test
    func promotesCandidateToActiveAfterStableSamples() {
        let detector = MeetingPresenceDetector(requiredStableSampleCount: 3)
        let sample = MeetingAppActivitySample(
            bundleIdentifier: "ru.tolk.desktop",
            isRunning: true,
            isFrontmost: true,
            hadRecentFocus: true,
            hasVisibleWindow: true,
            isUsingMedia: true
        )

        #expect(detector.evaluate(sample) == .candidateActive)
        #expect(detector.evaluate(sample) == .candidateActive)
        #expect(detector.evaluate(sample) == .activeMeeting)
    }
}
```

- [ ] **Step 2: Run the targeted detector test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingPresenceDetectorTests`

Expected: FAIL with missing detector or sample types.

- [ ] **Step 3: Add app-owned activity and presence models**

```swift
import Foundation

struct MeetingAppActivitySample: Equatable, Sendable {
    let bundleIdentifier: String
    let isRunning: Bool
    let isFrontmost: Bool
    let hadRecentFocus: Bool
    let hasVisibleWindow: Bool
    let isUsingMedia: Bool
}

enum MeetingAppPresence: Equatable, Sendable {
    case inactive
    case candidateActive
    case activeMeeting
    case ending
}
```

- [ ] **Step 4: Add the activity-source protocol and native source shell**

```swift
import AppKit
import Foundation

protocol MeetingAppActivitySource: Sendable {
    func sample(for app: AutoRecordingApp) -> MeetingAppActivitySample
}

struct NativeMeetingAppActivitySource: MeetingAppActivitySource {
    private let workspace: NSWorkspace
    private let runningApplications: () -> [NSRunningApplication]

    init(
        workspace: NSWorkspace = .shared,
        runningApplications: @escaping () -> [NSRunningApplication] = {
            NSWorkspace.shared.runningApplications
        }
    ) {
        self.workspace = workspace
        self.runningApplications = runningApplications
    }

    func sample(for app: AutoRecordingApp) -> MeetingAppActivitySample {
        let bundleIdentifier = "ru.tolk.desktop"
        let apps = runningApplications().filter { $0.bundleIdentifier == bundleIdentifier }
        let frontmostID = workspace.frontmostApplication?.bundleIdentifier

        return MeetingAppActivitySample(
            bundleIdentifier: bundleIdentifier,
            isRunning: !apps.isEmpty,
            isFrontmost: frontmostID == bundleIdentifier,
            hadRecentFocus: frontmostID == bundleIdentifier,
            hasVisibleWindow: !apps.isEmpty,
            isUsingMedia: false
        )
    }
}
```

- [ ] **Step 5: Add the initial detector implementation**

```swift
import Foundation

struct MeetingPresenceDetector {
    private let requiredStableSampleCount: Int
    private var stableMatchCount = 0

    init(requiredStableSampleCount: Int = 3) {
        self.requiredStableSampleCount = requiredStableSampleCount
    }

    mutating func evaluate(_ sample: MeetingAppActivitySample) -> MeetingAppPresence {
        let qualifies = sample.isRunning
            && sample.hasVisibleWindow
            && (sample.isUsingMedia || sample.isFrontmost || sample.hadRecentFocus)

        guard qualifies else {
            stableMatchCount = 0
            return .inactive
        }

        stableMatchCount += 1
        return stableMatchCount >= requiredStableSampleCount ? .activeMeeting : .candidateActive
    }
}
```

- [ ] **Step 6: Re-run the targeted detector test and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingPresenceDetectorTests`

Expected: PASS for the stable activation test.

- [ ] **Step 7: Commit the activity and detector foundation**

```bash
git add QuickMeeting/Models/MeetingAppPresence.swift QuickMeeting/Services/AutoRecording/MeetingAppActivitySource.swift QuickMeeting/Services/AutoRecording/NativeMeetingAppActivitySource.swift QuickMeeting/Services/AutoRecording/MeetingPresenceDetector.swift QuickMeetingTests/MeetingPresenceDetectorTests.swift
git commit -m "feat: add tolk meeting presence detector"
```

### Task 3: Add the auto-recording coordinator and timing rules

**Files:**
- Create: `QuickMeeting/Services/AutoRecording/AutoRecordingCoordinator.swift`
- Create: `QuickMeetingTests/AutoRecordingCoordinatorTests.swift`

- [ ] **Step 1: Write the failing coordinator test for delayed start and grace-period stop**

```swift
import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct AutoRecordingCoordinatorTests {
    @Test
    func startsAfterDelayAndStopsAfterGracePeriod() async {
        let clock = TestAutoRecordingClock()
        let sink = RecordingIntentSinkSpy()
        let coordinator = AutoRecordingCoordinator(
            clock: clock,
            intentSink: sink,
            startDelay: 10,
            stopGracePeriod: 60
        )

        await coordinator.handle(.candidateActive)
        await clock.advance(by: 9)
        #expect(sink.startRequests == 0)

        await coordinator.handle(.activeMeeting)
        await clock.advance(by: 1)
        #expect(sink.startRequests == 1)

        await coordinator.handle(.inactive)
        await clock.advance(by: 59)
        #expect(sink.stopRequests == 0)

        await clock.advance(by: 1)
        #expect(sink.stopRequests == 1)
    }
}
```

- [ ] **Step 2: Run the targeted coordinator test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingCoordinatorTests`

Expected: FAIL with missing coordinator, clock, or sink types.

- [ ] **Step 3: Add the coordinator boundary**

```swift
import Foundation

@MainActor
protocol AutoRecordingIntentSink: AnyObject {
    func requestAutoRecordingStart() async
    func requestAutoRecordingStop() async
}

protocol AutoRecordingClock: Sendable {
    func sleep(seconds: TimeInterval) async
}

struct TaskSleepAutoRecordingClock: AutoRecordingClock {
    func sleep(seconds: TimeInterval) async {
        let duration = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: duration)
    }
}
```

- [ ] **Step 4: Implement the coordinator with cancellation-aware timers**

```swift
import Foundation

@MainActor
final class AutoRecordingCoordinator {
    private let clock: AutoRecordingClock
    private weak var intentSink: (any AutoRecordingIntentSink)?
    private let startDelay: TimeInterval
    private let stopGracePeriod: TimeInterval
    private var isRecording = false
    private var pendingStartTask: Task<Void, Never>?
    private var pendingStopTask: Task<Void, Never>?

    init(
        clock: AutoRecordingClock = TaskSleepAutoRecordingClock(),
        intentSink: any AutoRecordingIntentSink,
        startDelay: TimeInterval,
        stopGracePeriod: TimeInterval
    ) {
        self.clock = clock
        self.intentSink = intentSink
        self.startDelay = startDelay
        self.stopGracePeriod = stopGracePeriod
    }

    func handle(_ presence: MeetingAppPresence) async {
        switch presence {
        case .candidateActive, .activeMeeting:
            pendingStopTask?.cancel()
            pendingStopTask = nil

            guard !isRecording, pendingStartTask == nil else {
                return
            }

            pendingStartTask = Task { [clock, startDelay, weak intentSink] in
                await clock.sleep(seconds: startDelay)
                await intentSink?.requestAutoRecordingStart()
            }
        case .inactive, .ending:
            pendingStartTask?.cancel()
            pendingStartTask = nil

            guard isRecording, pendingStopTask == nil else {
                return
            }

            pendingStopTask = Task { [clock, stopGracePeriod, weak intentSink] in
                await clock.sleep(seconds: stopGracePeriod)
                await intentSink?.requestAutoRecordingStop()
            }
        }
    }

    func recordingDidStart() {
        isRecording = true
        pendingStartTask?.cancel()
        pendingStartTask = nil
    }

    func recordingDidStop() {
        isRecording = false
        pendingStopTask?.cancel()
        pendingStopTask = nil
    }
}
```

- [ ] **Step 5: Re-run the targeted coordinator test and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingCoordinatorTests`

Expected: PASS for delayed start and grace-period stop behavior.

- [ ] **Step 6: Add a second failing test for stop cancellation**

```swift
@Test
func returningActivityCancelsPendingStop() async {
    let clock = TestAutoRecordingClock()
    let sink = RecordingIntentSinkSpy()
    let coordinator = AutoRecordingCoordinator(
        clock: clock,
        intentSink: sink,
        startDelay: 10,
        stopGracePeriod: 60
    )

    coordinator.recordingDidStart()
    await coordinator.handle(.inactive)
    await clock.advance(by: 30)
    await coordinator.handle(.activeMeeting)
    await clock.advance(by: 40)

    #expect(sink.stopRequests == 0)
}
```

- [ ] **Step 7: Re-run the same targeted suite and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingCoordinatorTests`

Expected: PASS for both coordinator timing tests.

- [ ] **Step 8: Commit the coordinator logic**

```bash
git add QuickMeeting/Services/AutoRecording/AutoRecordingCoordinator.swift QuickMeetingTests/AutoRecordingCoordinatorTests.swift
git commit -m "feat: add auto recording coordinator"
```

### Task 4: Wire auto-recording into the app view model and shell

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeeting/Views/HomeView.swift`
- Modify: `QuickMeeting/MenuBar/MenuBarView.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing app-view-model test for auto-start reuse**

```swift
@Test
func autoRecordingStartUsesExistingRecordingPath() async throws {
    let harness = try AppViewModelTestHarness()
    let meetingID = UUID()
    var meetingIDs = [meetingID]
    let viewModel = AppViewModel(
        meetingStore: harness.meetingStore,
        meetingFileStore: harness.meetingFileStore,
        recordingService: harness.recordingService,
        recordingPermissions: harness.recordingPermissions,
        meetingIDProvider: { meetingIDs.removeFirst() }
    )

    await viewModel.requestAutoRecordingStart()

    #expect(viewModel.recordingState == .recording(meetingID: meetingID))
    #expect(viewModel.autoRecordingStatusText == "Recording started automatically")
}
```

- [ ] **Step 2: Run the targeted app-view-model suite and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: FAIL with missing auto-recording entry points or status text.

- [ ] **Step 3: Add app-facing auto-recording status on `AppViewModel`**

```swift
@Published private(set) var autoRecordingStatusText: String?
private var autoRecordingCoordinator: AutoRecordingCoordinator?

func attachAutoRecordingCoordinator(_ coordinator: AutoRecordingCoordinator) {
    autoRecordingCoordinator = coordinator
}

func updateAutoRecordingPresence(_ presence: MeetingAppPresence) async {
    switch presence {
    case .candidateActive:
        autoRecordingStatusText = "Detected meeting activity in Толк, waiting 10s"
    case .activeMeeting:
        autoRecordingStatusText = "Detected meeting activity in Толк, waiting 10s"
    case .ending:
        autoRecordingStatusText = "Meeting activity lost, stopping soon"
    case .inactive:
        autoRecordingStatusText = nil
    }

    await autoRecordingCoordinator?.handle(presence)
}
```

- [ ] **Step 4: Make `AppViewModel` the coordinator intent sink**

```swift
extension AppViewModel: AutoRecordingIntentSink {
    func requestAutoRecordingStart() async {
        guard canStartRecording else {
            return
        }

        autoRecordingStatusText = "Recording started automatically"
        await startRecording()
        if case .recording = recordingState {
            autoRecordingCoordinator?.recordingDidStart()
        }
    }

    func requestAutoRecordingStop() async {
        guard canStopRecording else {
            return
        }

        await stopRecording()
        if case .idle = recordingState {
            autoRecordingStatusText = nil
            autoRecordingCoordinator?.recordingDidStop()
        }
    }
}
```

- [ ] **Step 5: Wire the monitor and coordinator in `QuickMeetingApp`**

```swift
let autoRecordingStore = AutoRecordingSettingsStore()
let autoRecordingSettings = autoRecordingStore.load()
let activitySource = NativeMeetingAppActivitySource()
let coordinator = AutoRecordingCoordinator(
    intentSink: appViewModel,
    startDelay: autoRecordingSettings.startDelay,
    stopGracePeriod: autoRecordingSettings.stopGracePeriod
)

_appViewModel = StateObject(
    wrappedValue: AppViewModel(
        meetingStore: meetingStore,
        meetingFileStore: meetingFileStore,
        recordingService: recordingService,
        transcriptionService: transcriptionService,
        transcriptionProgressCenter: transcriptionProgressCenter,
        meetingTranscriptStore: meetingTranscriptStore,
        calendarIntegration: calendarIntegration
    )
)

_appViewModel.wrappedValue.attachAutoRecordingCoordinator(coordinator)
```

- [ ] **Step 6: Surface the status in Home and the menu bar**

```swift
if let autoRecordingStatusText = appViewModel.autoRecordingStatusText {
    Text(autoRecordingStatusText)
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 7: Re-run the targeted app-view-model suite and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: PASS for the new auto-recording start reuse test and existing recording tests.

- [ ] **Step 8: Commit the app wiring**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/QuickMeetingApp.swift QuickMeeting/Views/HomeView.swift QuickMeeting/MenuBar/MenuBarView.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: wire auto recording into app shell"
```

### Task 5: Add Settings UI and runtime polling control

**Files:**
- Create: `QuickMeeting/ViewModels/AutoRecordingSettingsViewModel.swift`
- Create: `QuickMeeting/Views/Settings/AutoRecordingSettingsSections.swift`
- Create: `QuickMeetingTests/AutoRecordingSettingsViewModelTests.swift`
- Modify: `QuickMeeting/Views/Settings/SettingsView.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`

- [ ] **Step 1: Write the failing settings-view-model test**

```swift
import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct AutoRecordingSettingsViewModelTests {
    @Test
    func savePersistsUpdatedAutoRecordingSettings() async {
        let store = InMemoryAutoRecordingSettingsStore(
            settings: .default
        )
        let viewModel = AutoRecordingSettingsViewModel(settingsStore: store)

        await viewModel.load()
        viewModel.isEnabled = true
        viewModel.stopGracePeriod = 90
        await viewModel.save()

        #expect(store.settings.isEnabled == true)
        #expect(store.settings.stopGracePeriod == 90)
    }
}
```

- [ ] **Step 2: Run the targeted settings-view-model test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsViewModelTests`

Expected: FAIL with missing auto-recording settings view model.

- [ ] **Step 3: Add the settings view model**

```swift
import Foundation

@MainActor
final class AutoRecordingSettingsViewModel: ObservableObject {
    @Published var isEnabled = false
    @Published var selectedApp: AutoRecordingApp = .tolk
    @Published var startDelay: Double = 10
    @Published var stopGracePeriod: Double = 60

    private let settingsStore: any AutoRecordingSettingsStoring

    init(settingsStore: any AutoRecordingSettingsStoring) {
        self.settingsStore = settingsStore
    }

    func load() async {
        let settings = settingsStore.load()
        isEnabled = settings.isEnabled
        selectedApp = settings.selectedApp
        startDelay = settings.startDelay
        stopGracePeriod = settings.stopGracePeriod
    }

    func save() async {
        settingsStore.save(
            AutoRecordingSettings(
                isEnabled: isEnabled,
                selectedApp: selectedApp,
                startDelay: startDelay,
                stopGracePeriod: stopGracePeriod
            )
        )
    }
}
```

- [ ] **Step 4: Add the settings sections UI**

```swift
import SwiftUI

struct AutoRecordingSettingsSections: View {
    @ObservedObject var viewModel: AutoRecordingSettingsViewModel

    var body: some View {
        Section("Auto Recording") {
            Toggle("Enable auto recording", isOn: $viewModel.isEnabled)
            Picker("Watched app", selection: $viewModel.selectedApp) {
                ForEach(AutoRecordingApp.allCases, id: \.self) { app in
                    Text(app.displayName).tag(app)
                }
            }
            HStack {
                Text("Start delay")
                Spacer()
                Text("\(Int(viewModel.startDelay))s")
            }
            Slider(value: $viewModel.startDelay, in: 5 ... 20, step: 1)
            HStack {
                Text("Stop grace period")
                Spacer()
                Text("\(Int(viewModel.stopGracePeriod))s")
            }
            Slider(value: $viewModel.stopGracePeriod, in: 30 ... 120, step: 5)
        }
        .onChange(of: viewModel.isEnabled) { _, _ in
            Task { await viewModel.save() }
        }
        .onChange(of: viewModel.selectedApp) { _, _ in
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

- [ ] **Step 5: Wire the new settings section into `SettingsView`**

```swift
struct SettingsView: View {
    @ObservedObject var modelsViewModel: ModelsSettingsViewModel
    @ObservedObject var calendarViewModel: CalendarSettingsViewModel
    @ObservedObject var autoRecordingViewModel: AutoRecordingSettingsViewModel

    var body: some View {
        Form {
            AutoRecordingSettingsSections(viewModel: autoRecordingViewModel)
            CalendarSettingsSections(viewModel: calendarViewModel)
            ModelsSettingsSections(
                viewModel: modelsViewModel,
                pendingDeleteModelID: $pendingDeleteModelID
            )
        }
        .task {
            await autoRecordingViewModel.load()
            await calendarViewModel.reload()
            await modelsViewModel.load()
        }
    }
}
```

- [ ] **Step 6: Re-run the targeted settings-view-model suite and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsViewModelTests`

Expected: PASS for the new settings persistence test.

- [ ] **Step 7: Commit the settings UI**

```bash
git add QuickMeeting/ViewModels/AutoRecordingSettingsViewModel.swift QuickMeeting/Views/Settings/AutoRecordingSettingsSections.swift QuickMeeting/Views/Settings/SettingsView.swift QuickMeetingTests/AutoRecordingSettingsViewModelTests.swift QuickMeeting/QuickMeetingApp.swift
git commit -m "feat: add auto recording settings UI"
```

### Task 6: Final verification and architecture doc update

**Files:**
- Modify: `docs/quickmeeting-architecture-design.md`
- Test: `QuickMeetingTests/MeetingPresenceDetectorTests.swift`
- Test: `QuickMeetingTests/AutoRecordingCoordinatorTests.swift`
- Test: `QuickMeetingTests/AutoRecordingSettingsStoreTests.swift`
- Test: `QuickMeetingTests/AutoRecordingSettingsViewModelTests.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Update the architecture doc**

```md
### Auto Recording

- `NativeMeetingAppActivitySource` samples native app activity for supported meeting apps.
- `MeetingPresenceDetector` converts sampled activity into app-owned meeting presence states.
- `AutoRecordingCoordinator` applies confirmation and grace-period timing before calling the same `AppViewModel` recording flow used by manual UI controls.
- Auto recording is optional, settings-backed, and currently tuned for the native `Толк` app.
```

- [ ] **Step 2: Run the focused auto-recording suites**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsStoreTests -only-testing:QuickMeetingTests/MeetingPresenceDetectorTests -only-testing:QuickMeetingTests/AutoRecordingCoordinatorTests -only-testing:QuickMeetingTests/AutoRecordingSettingsViewModelTests -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: PASS across all targeted auto-recording and recording-lifecycle suites.

- [ ] **Step 3: Commit the documentation and verification pass**

```bash
git add docs/quickmeeting-architecture-design.md
git commit -m "docs: record auto recording architecture"
```

## Self-Review

### Spec coverage

- Auto-recording enablement, app selection, start-delay default, and stop-grace default are covered in Task 1 and Task 5.
- `Толк`-specific native activity sampling and system-level heuristic evaluation are covered in Task 2.
- The 10-second start confirmation and 60-second stop grace logic are covered in Task 3.
- Reuse of the existing manual recording flow and visible runtime status are covered in Task 4.
- Testing and architecture documentation are covered in Task 6.

### Placeholder scan

- No `TBD`, `TODO`, or “implement later” placeholders remain.
- Every code-writing step includes concrete code or a concrete interface shape.
- Every verification step includes an exact command and expected result.

### Type consistency

- `AutoRecordingSettings`, `AutoRecordingApp`, `MeetingAppActivitySample`, and `MeetingAppPresence` are defined before later tasks rely on them.
- The coordinator uses the same `MeetingAppPresence` states introduced in Task 2.
- The UI tasks reuse the same `AutoRecordingSettingsViewModel` and `AppViewModel` entry points established earlier in the plan.

This plan intentionally keeps the first implementation focused on native `Толк` detection and does not include generic browser handling or network-traffic heuristics.
