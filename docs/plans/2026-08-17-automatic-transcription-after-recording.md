**Goal:** Let users opt in to automatically start transcription after a recording ends successfully.

**Architecture:** Extend the existing `TranscriptionPipelineOptions` persistence and settings view model with one false-by-default flag. Inject the existing transcription settings store into `AppViewModel`; after its normal successful recording-finish path, it conditionally starts the same `transcribeMeeting(_:)` workflow in a task, keeping recording state management separate from asynchronous transcription work.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, `UserDefaults`, Swift Testing, Xcode.

---

### Task 1: Persist the automatic-transcription preference

**Files:**
- Modify: `QuickMeeting/Models/StoredTranscript.swift:39-55`
- Modify: `QuickMeeting/Services/Transcription/TranscriptionSettingsStore.swift:12-56`
- Test: `QuickMeetingTests/TranscriptionSettingsStoreTests.swift:5-37`

- [ ] **Step 1: Write the failing persistence tests**

Update the expected defaults and round-trip values, and add a focused test that writes only the new option:

```swift
@Test
func automaticTranscriptionDefaultsToDisabled() {
    let store = TranscriptionSettingsStore(userDefaults: makeDefaults())

    #expect(store.pipelineOptions().isAutomaticTranscriptionEnabled == false)
}

@Test
func automaticTranscriptionRoundTripsWithPipelineOptions() {
    let store = TranscriptionSettingsStore(userDefaults: makeDefaults())
    store.savePipelineOptions(.init(isAutomaticTranscriptionEnabled: true))

    #expect(store.pipelineOptions().isAutomaticTranscriptionEnabled == true)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting-Test -destination 'platform=macOS' -derivedDataPath .derived-data-automatic-transcription CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionSettingsStoreTests 2>&1 | xcsift -f toon
```

Expected: compilation fails because `isAutomaticTranscriptionEnabled` does not exist.

- [ ] **Step 3: Implement the minimal option and persistence**

Add the flag with a false default to `TranscriptionPipelineOptions`:

```swift
var isAutomaticTranscriptionEnabled: Bool

init(
    languageCode: String? = nil,
    ctcMode: TranscriptionCTCMode = .off,
    isLLMCorrectionEnabled: Bool = false,
    isAutomaticTranscriptionEnabled: Bool = false
) {
    self.languageCode = languageCode
    self.ctcMode = ctcMode
    self.isLLMCorrectionEnabled = isLLMCorrectionEnabled
    self.isAutomaticTranscriptionEnabled = isAutomaticTranscriptionEnabled
}
```

In `TranscriptionSettingsStore`, add `transcription.automaticTranscriptionEnabled`, read it with `UserDefaults.bool(forKey:)`, and save it together with the existing pipeline options.

- [ ] **Step 4: Run the test to verify it passes**

Run the command from Step 2.

Expected: `TranscriptionSettingsStoreTests` passes and the build succeeds.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Models/StoredTranscript.swift QuickMeeting/Services/Transcription/TranscriptionSettingsStore.swift QuickMeetingTests/TranscriptionSettingsStoreTests.swift
git commit -m "feat: persist automatic transcription setting"
```

### Task 2: Expose the setting in the transcription controls

**Files:**
- Modify: `QuickMeeting/ViewModels/TranscriptionSettingsViewModel.swift:13-99`
- Modify: `QuickMeeting/Views/Settings/QMSettingsSheet.swift:167-235`
- Test: `QuickMeetingTests/TranscriptionSettingsViewModelTests.swift:6-28`

- [ ] **Step 1: Write the failing view-model test**

Add a test that ensures toggling the preference preserves the other pipeline fields:

```swift
@Test
func automaticTranscriptionTogglePersistsAlongsidePipelineOptions() {
    let defaults = makeDefaults()
    let store = TranscriptionSettingsStore(userDefaults: defaults)
    let viewModel = TranscriptionSettingsViewModel(
        settingsStore: store,
        glossaryStore: TranscriptionGlossaryStore(userDefaults: defaults)
    )

    viewModel.selectLanguage(code: "de")
    viewModel.selectCTCMode(.ctc110m)
    viewModel.setLLMCorrectionEnabled(true)
    viewModel.setAutomaticTranscriptionEnabled(true)

    #expect(store.pipelineOptions() == .init(
        languageCode: "de",
        ctcMode: .ctc110m,
        isLLMCorrectionEnabled: true,
        isAutomaticTranscriptionEnabled: true
    ))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting-Test -destination 'platform=macOS' -derivedDataPath .derived-data-automatic-transcription CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionSettingsViewModelTests 2>&1 | xcsift -f toon
```

Expected: compilation fails because the view model has no automatic-transcription property or setter.

- [ ] **Step 3: Implement the view-model state and Settings row**

Load the persisted flag in the initializer, add the published property and setter, and preserve it in `savePipelineOptions()`:

```swift
@Published private(set) var isAutomaticTranscriptionEnabled: Bool

func setAutomaticTranscriptionEnabled(_ isEnabled: Bool) {
    isAutomaticTranscriptionEnabled = isEnabled
    savePipelineOptions()
}
```

Add a `QMToggle` row to `transcriptionSection` below the LLM correction row. Bind it to the setter and use the copy `Automatically transcribe after recording` and `Starts transcription when a recording ends.`

- [ ] **Step 4: Run the test to verify it passes**

Run the command from Step 2.

Expected: `TranscriptionSettingsViewModelTests` passes and the build succeeds.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/ViewModels/TranscriptionSettingsViewModel.swift QuickMeeting/Views/Settings/QMSettingsSheet.swift QuickMeetingTests/TranscriptionSettingsViewModelTests.swift
git commit -m "feat: add automatic transcription setting control"
```

### Task 3: Trigger transcription after successful recording completion

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift:37-96, 159-182`
- Modify: `QuickMeeting/QuickMeetingApp.swift:57-104`
- Test: `QuickMeetingTests/AppViewModelTests.swift:8-84, 335-630`

- [ ] **Step 1: Write the failing lifecycle tests and test doubles**

Add a `StubTranscriptionService` that records meeting IDs, pass it and a `TranscriptionSettingsStore` into `AppViewModelHarness`, and add tests for enabled manual, enabled automatic, disabled, and failed-stop paths. The manual enabled test should look like:

```swift
@Test
func finishingRecordingStartsTranscriptionWhenEnabled() async throws {
    let transcriptionService = StubTranscriptionService()
    let settingsStore = makeTranscriptionSettingsStore(isAutomaticEnabled: true)
    let harness = try AppViewModelHarness(
        transcriptionService: transcriptionService,
        transcriptionSettingsStore: settingsStore
    )

    await harness.viewModel.startRecording()
    let meetingID = try #require(harness.viewModel.activeOrRecoverableMeetingID)
    await harness.viewModel.stopRecording()
    await Task.yield()

    #expect(transcriptionService.meetingIDs == [meetingID])
    #expect(harness.viewModel.recordingState == .idle)
}
```

The automatic test calls `requestAutoRecordingStart()` then `requestAutoRecordingStop()`. The disabled test expects no IDs. For the failed-stop test, add a throwing recorder and assert no IDs and `.failed` state.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting-Test -destination 'platform=macOS' -derivedDataPath .derived-data-automatic-transcription CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests 2>&1 | xcsift -f toon
```

Expected: compilation fails because the harness and `AppViewModel` do not accept the transcription settings dependency.

- [ ] **Step 3: Implement the post-recording trigger**

Inject and store `any TranscriptionLanguageStoring` in `AppViewModel`, defaulting to `TranscriptionSettingsStore()`. Once `finishRecording` succeeds and the UI state has been returned to idle, start the existing method only when the setting is enabled:

```swift
if transcriptionSettingsStore.pipelineOptions().isAutomaticTranscriptionEnabled {
    Task { [weak self, weak meeting] in
        guard let self, let meeting else { return }
        await self.transcribeMeeting(meeting)
    }
}
```

Pass the shared `transcriptionSettingsStore` from `QuickMeetingApp` to `AppViewModel`, so Settings and the recording lifecycle read the same preference.

- [ ] **Step 4: Run the test to verify it passes**

Run the command from Step 2.

Expected: all added lifecycle tests pass; the disabled and failure cases record no transcription calls.

- [ ] **Step 5: Run focused regression coverage**

Run:

```bash
xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting-Test -destination 'platform=macOS' -derivedDataPath .derived-data-automatic-transcription CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionSettingsStoreTests -only-testing:QuickMeetingTests/TranscriptionSettingsViewModelTests -only-testing:QuickMeetingTests/AppViewModelTests 2>&1 | xcsift -f toon
```

Expected: all three selected suites pass and the build succeeds.

- [ ] **Step 6: Commit**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: transcribe recordings automatically"
```
