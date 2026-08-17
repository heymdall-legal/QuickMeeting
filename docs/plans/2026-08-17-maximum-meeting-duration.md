**Goal:** Automatically finish every recording after a configurable whole-hour maximum duration, defaulting to three hours.

**Architecture:** Add the duration to the existing auto-recording settings model, store, view model, and Settings UI. Give `AppViewModel`, which owns every recording lifecycle, an injected one-shot deadline scheduler; it loads the saved duration when a recording starts, schedules `stopRecording()`, and cancels that task for every stop outcome.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, SwiftData, UserDefaults.

---

### Task 1: Persist the maximum duration setting

**Files:**
- Modify: `QuickMeeting/Models/AutoRecordingSettings.swift:49-91`
- Modify: `QuickMeeting/Services/AutoRecording/AutoRecordingSettingsStore.swift:17-45`
- Test: `QuickMeetingTests/AutoRecordingSettingsStoreTests.swift:5-37`

- [ ] **Step 1: Write the failing store regression test**

  Extend `settingsRoundTripWithMultipleTargets()` with the assertions and constructor argument below:

  ```swift
  #expect(store.load().maximumMeetingDurationHours == 3)

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
      stopGracePeriod: 75,
      maximumMeetingDurationHours: 5
  )

  #expect(store.load() == updated)
  ```

- [ ] **Step 2: Run the targeted test and verify it fails**

  Run:

  ```bash
  rtk xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-maximum-meeting-duration CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsStoreTests | rtk rg 'error:|warning:|passed|failed|Executed [0-9]+ tests|BUILD SUCCEEDED|BUILD FAILED'
  ```

  Expected: compilation fails because `maximumMeetingDurationHours` does not exist.

- [ ] **Step 3: Add the model property and persistence key**

  Add an integer model property and initializer parameter (defaulting to `3` so
  existing construction sites remain source-compatible), preserve it through
  the legacy `selectedApp` initializer, and set the default to `3`:

  ```swift
  var maximumMeetingDurationHours: Int

  init(
      isEnabled: Bool,
      selectedApps: [AutoRecordingTarget],
      startDelay: TimeInterval,
      stopGracePeriod: TimeInterval,
      maximumMeetingDurationHours: Int = 3
  )

  static let `default` = AutoRecordingSettings(
      isEnabled: false,
      selectedApps: [],
      startDelay: 10,
      stopGracePeriod: 60,
      maximumMeetingDurationHours: 3
  )
  ```

  Add `maximumMeetingDurationKey = "autoRecording.maximumMeetingDurationHours"` to `AutoRecordingSettingsStore`. Read it with `integer(forKey:)` only when `object(forKey:)` is present, falling back to `defaults.maximumMeetingDurationHours`; save it with `userDefaults.set(settings.maximumMeetingDurationHours, forKey: maximumMeetingDurationKey)`.

- [ ] **Step 4: Run the targeted test and verify it passes**

  Re-run the command from Step 2.

  Expected: `AutoRecordingSettingsStoreTests` passes and `BUILD SUCCEEDED` appears.

- [ ] **Step 5: Commit the settings persistence change**

  ```bash
  git add QuickMeeting/Models/AutoRecordingSettings.swift QuickMeeting/Services/AutoRecording/AutoRecordingSettingsStore.swift QuickMeetingTests/AutoRecordingSettingsStoreTests.swift
  git commit -m "feat: persist maximum meeting duration"
  ```

### Task 2: Expose whole hours in Settings

**Files:**
- Modify: `QuickMeeting/ViewModels/AutoRecordingSettingsViewModel.swift:12-53`
- Modify: `QuickMeeting/Views/Settings/QMSettingsSheet.swift:607-625`
- Test: `QuickMeetingTests/AutoRecordingSettingsViewModelTests.swift:5-140`

- [ ] **Step 1: Write the failing view-model test**

  Add a test that seeds the in-memory store with five hours, calls `load()`, changes the published value to six, then calls `save()`:

  ```swift
  @Test
  func loadAndSaveExposeMaximumMeetingDurationHours() async {
      let store = InMemoryAutoRecordingSettingsStore(
          settings: AutoRecordingSettings(
              isEnabled: false,
              selectedApps: [],
              startDelay: 10,
              stopGracePeriod: 60,
              maximumMeetingDurationHours: 5
          )
      )
      let viewModel = AutoRecordingSettingsViewModel(settingsStore: store)

      await viewModel.load()
      #expect(viewModel.maximumMeetingDurationHours == 5)
      viewModel.maximumMeetingDurationHours = 6
      await viewModel.save()
      #expect(store.settings.maximumMeetingDurationHours == 6)
  }
  ```

- [ ] **Step 2: Run the targeted test and verify it fails**

  Run:

  ```bash
  rtk xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-maximum-meeting-duration CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsViewModelTests | rtk rg 'error:|warning:|passed|failed|Executed [0-9]+ tests|BUILD SUCCEEDED|BUILD FAILED'
  ```

  Expected: compilation fails because the view model has no duration property.

- [ ] **Step 3: Add the published value and Settings stepper**

  In `AutoRecordingSettingsViewModel`, add:

  ```swift
  @Published var maximumMeetingDurationHours = 3
  ```

  Assign it from `settings` in `load()` and include it in the `AutoRecordingSettings` value in `save()`.

  Add an `Int` overload of `stepperRow` adjacent to the existing `Binding<Double>`
  helper, preserving its layout and using `Int` arithmetic. In the visible
  auto-recording settings block, add a whole-hour stepper and persistence
  trigger:

  ```swift
  stepperRow(
      title: "Maximum meeting duration",
      value: $autoRecordingViewModel.maximumMeetingDurationHours,
      range: 1...24, step: 1, unit: "hours"
  )

  .onChange(of: autoRecordingViewModel.maximumMeetingDurationHours) { _, _ in save() }
  ```

- [ ] **Step 4: Run the targeted test and verify it passes**

  Re-run the command from Step 2.

  Expected: `AutoRecordingSettingsViewModelTests` passes and `BUILD SUCCEEDED` appears.

- [ ] **Step 5: Commit the Settings exposure change**

  ```bash
  git add QuickMeeting/ViewModels/AutoRecordingSettingsViewModel.swift QuickMeeting/Views/Settings/QMSettingsSheet.swift QuickMeetingTests/AutoRecordingSettingsViewModelTests.swift
  git commit -m "feat: configure maximum meeting duration"
  ```

### Task 3: Stop recordings at their configured deadline

**Files:**
- Create: `QuickMeeting/Services/Recording/RecordingDeadlineClock.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift:30-170`
- Modify: `QuickMeeting/QuickMeetingApp.swift:79-99`
- Test: `QuickMeetingTests/AppViewModelTests.swift:5-354`

- [ ] **Step 1: Write failing lifecycle tests and deterministic test clock**

  Add `TestRecordingDeadlineClock` and a cancellable scheduled-task spy to `AppViewModelTests.swift`. Extend `AppViewModelHarness` to accept an `AutoRecordingSettingsStoring`, a `RecordingDeadlineClock`, and a `StubRecordingService` it exposes to tests. Add these tests:

  ```swift
  @MainActor
  private final class TestRecordingDeadlineClock: RecordingDeadlineClock {
      private var now: TimeInterval = 0
      private var operations: [(deadline: TimeInterval, task: TestDeadlineTask, operation: @MainActor @Sendable () async -> Void)] = []

      func schedule(after seconds: TimeInterval, operation: @escaping @MainActor @Sendable () async -> Void) -> any RecordingDeadlineScheduledTask {
          let task = TestDeadlineTask()
          operations.append((now + seconds, task, operation))
          return task
      }

      func advance(by seconds: TimeInterval) async {
          now += seconds
          let ready = operations.filter { $0.deadline <= now }
          operations.removeAll { $0.deadline <= now }
          for item in ready where !item.task.isCancelled { await item.operation() }
      }
  }

  private final class TestDeadlineTask: RecordingDeadlineScheduledTask, @unchecked Sendable {
      private(set) var isCancelled = false
      func cancel() { isCancelled = true }
  }
  ```

  ```swift
  @Test
  func recordingStopsWhenMaximumDurationExpires() async throws {
      let clock = TestRecordingDeadlineClock()
      let recorder = StubRecordingService()
      let harness = try AppViewModelHarness(
          recorder: recorder,
          autoRecordingSettings: .init(
              isEnabled: false, selectedApps: [], startDelay: 10,
              stopGracePeriod: 60, maximumMeetingDurationHours: 3
          ),
          deadlineClock: clock
      )

      await harness.viewModel.startRecording()
      await clock.advance(by: 10_799)
      #expect(recorder.stopCalls == 0)
      await clock.advance(by: 1)
      #expect(recorder.stopCalls == 1)
      #expect(harness.viewModel.recordingState == .idle)
  }

  @Test
  func stoppingBeforeMaximumDurationCancelsDeadline() async throws {
      let clock = TestRecordingDeadlineClock()
      let recorder = StubRecordingService()
      let harness = try AppViewModelHarness(recorder: recorder, deadlineClock: clock)

      await harness.viewModel.startRecording()
      await harness.viewModel.stopRecording()
      await clock.advance(by: 10_800)
      #expect(recorder.stopCalls == 1)
  }
  ```

  Add a third test that calls `await harness.viewModel.requestAutoRecordingStart()`, advances the same deadline clock, and asserts `stopCalls == 1`; this proves the shared deadline also covers automatic starts.

- [ ] **Step 2: Run the targeted lifecycle tests and verify they fail**

  Run:

  ```bash
  rtk xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-maximum-meeting-duration CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/AutoRecordingCoordinatorTests | rtk rg 'error:|warning:|passed|failed|Executed [0-9]+ tests|BUILD SUCCEEDED|BUILD FAILED'
  ```

  Expected: compilation fails because deadline scheduling is unavailable from `AppViewModel`.

- [ ] **Step 3: Implement a one-shot recording deadline and wire it into the lifecycle**

  Create `RecordingDeadlineClock.swift` with this main-actor scheduler protocol and production `Task.sleep` implementation:

  ```swift
  @MainActor
  protocol RecordingDeadlineClock: Sendable {
      func schedule(
          after seconds: TimeInterval,
          operation: @escaping @MainActor @Sendable () async -> Void
      ) -> any RecordingDeadlineScheduledTask
  }

  protocol RecordingDeadlineScheduledTask { func cancel() }

  @MainActor
  struct TaskSleepRecordingDeadlineClock: RecordingDeadlineClock {
      func schedule(after seconds: TimeInterval, operation: @escaping @MainActor @Sendable () async -> Void) -> any RecordingDeadlineScheduledTask {
          let task = Task {
              try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
              guard !Task.isCancelled else { return }
              await operation()
          }
          return RecordingDeadlineTaskHandle { task.cancel() }
      }
  }

  private struct RecordingDeadlineTaskHandle: RecordingDeadlineScheduledTask {
      let cancellation: @Sendable () -> Void
      func cancel() { cancellation() }
  }
  ```

  Add `autoRecordingSettingsStore` and `recordingDeadlineClock` constructor dependencies to `AppViewModel`, with production defaults. Keep `private var maximumDurationTask: (any RecordingDeadlineScheduledTask)?`.

  Immediately after setting `recordingState = .recording`, load the current setting, schedule `Double(hours) * 3_600`, and have the scheduled operation weakly capture the view model and call `await self?.stopRecording()`. Implement a private `cancelMaximumDurationTask()` that cancels then clears the task.

  Call the cancellation helper at the beginning of `stopRecording()` after resolving the active ID, and in the `startRecording()` failure path before reporting `.failed`. This makes normal manual stops, automatic activity stops, deadline stops, and failed starts mutually exclusive.

  Pass the shared `autoRecordingSettingsStore` into the production `AppViewModel` initializer in `QuickMeetingApp`. Leave previews on the safe default dependency.

- [ ] **Step 4: Run the targeted lifecycle tests and verify they pass**

  Re-run the command from Step 2.

  Expected: `AppViewModelTests` and `AutoRecordingCoordinatorTests` pass, with `BUILD SUCCEEDED`.

- [ ] **Step 5: Run the full relevant regression set**

  Run:

  ```bash
  rtk xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-maximum-meeting-duration CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AutoRecordingSettingsStoreTests -only-testing:QuickMeetingTests/AutoRecordingSettingsViewModelTests -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/AutoRecordingCoordinatorTests -only-testing:QuickMeetingTests/MeetingAppMonitorTests | rtk rg 'error:|warning:|passed|failed|Executed [0-9]+ tests|BUILD SUCCEEDED|BUILD FAILED'
  ```

  Expected: all selected suites pass and `BUILD SUCCEEDED` appears.

- [ ] **Step 6: Commit the deadline enforcement change**

  ```bash
  git add QuickMeeting/Services/Recording/RecordingDeadlineClock.swift QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/AppViewModelTests.swift
  git commit -m "feat: stop recordings at maximum duration"
  ```
