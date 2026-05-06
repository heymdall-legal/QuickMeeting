**Goal:** Allow users to rerun transcription on completed meetings after an overwrite warning, clearing the old transcript only when the new transcription officially starts.

**Architecture:** Extend the existing transcription pipeline rather than introducing a separate rerun system. The UI adds a confirmation alert for completed meetings, while `AppViewModel`, `TranscriptionService`, `MeetingStore`, and `Meeting` expand the existing transcription lifecycle to accept completed meetings and clear transcript metadata when transcription starts.

**Tech Stack:** Swift, SwiftUI, SwiftData, Testing, xcodebuild

---

## File Structure

- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
  Adds the overwrite confirmation alert and routes the `Transcribe` button through either direct start or confirmation-first start.
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
  Expands transcribable meeting eligibility so completed meetings can rerun transcription.
- Modify: `QuickMeeting/Services/Transcription/TranscriptionService.swift`
  Allows completed meetings through service-level validation while preserving the existing validation order.
- Modify: `QuickMeeting/Services/MeetingStore.swift`
  Keeps `startTranscription` as the single persistence transition into `transcribing`, including transcript metadata reset.
- Modify: `QuickMeeting/Models/Meeting.swift`
  Clears `transcriptFilePath` and `transcriptPreview` as part of beginning transcription.
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
  Covers completed-meeting eligibility.
- Modify: `QuickMeetingTests/MeetingStoreTests.swift`
  Covers clearing transcript metadata when transcription starts on a meeting that already has a transcript.
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`
  Covers successful retranscription of completed meetings and protects against transcript clearing when validation fails before start.

### Task 1: Expand rerun eligibility in the domain layer

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/Services/Transcription/TranscriptionService.swift`

- [ ] **Step 1: Write the failing `AppViewModel` eligibility test**

```swift
@Test
func canTranscribeMeetingReturnsTrueForCompletedMeeting() async throws {
    let harness = try AppViewModelTestHarness()
    let meeting = try harness.createMeeting(status: .completed)
    let viewModel = AppViewModel(
        meetingStore: harness.meetingStore,
        meetingFileStore: harness.meetingFileStore,
        recordingService: harness.recordingService,
        transcriptionService: harness.transcriptionService,
        transcriptionProgressCenter: harness.transcriptionProgressCenter,
        recordingPermissions: harness.recordingPermissions
    )

    #expect(viewModel.canTranscribeMeeting(meeting))
}
```

- [ ] **Step 2: Run the focused `AppViewModel` test to confirm it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcription-rerun "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: FAIL because `canTranscribeMeeting(_:)` currently rejects `.completed`.

- [ ] **Step 3: Write the failing `TranscriptionService` retranscription test**

Add a new test next to the existing recorded-meeting success case:

```swift
@Test
func transcribeCompletedMeetingClearsAndReplacesTranscript() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createCompletedMeeting(
        transcriptText: "Old transcript",
        preview: "Old transcript"
    )
    await harness.installDefaultModel(.small)
    await harness.backend.setResult(.success(
        TranscriptionResult(
            fullText: "New transcript",
            segments: [TranscriptSegment(text: "New transcript", startTime: 0, endTime: 1)]
        )
    ))

    try await harness.service.transcribe(meetingID: meeting.id)

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .completed)
    #expect(reloaded.transcriptPreview == "New transcript")
    let transcriptPath = try #require(reloaded.transcriptFilePath)
    #expect(try String(contentsOfFile: transcriptPath) == "New transcript")
}
```

- [ ] **Step 4: Run the focused `TranscriptionService` test to confirm it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcription-rerun "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: FAIL because `TranscriptionService.transcribe(meetingID:)` currently rejects meetings with status `.completed`.

- [ ] **Step 5: Update `AppViewModel` to allow completed meetings**

Change `QuickMeeting/ViewModels/AppViewModel.swift`:

```swift
func canTranscribeMeeting(_ meeting: Meeting) -> Bool {
    guard let status = try? meeting.status else {
        return false
    }

    switch status {
    case .recorded, .failed, .completed:
        return true
    case .recording, .transcribing:
        return false
    }
}
```

- [ ] **Step 6: Update `TranscriptionService` to allow completed meetings**

Change the status gate in `QuickMeeting/Services/Transcription/TranscriptionService.swift`:

```swift
let meeting = try meetingStore.fetchMeeting(id: meetingID)
let status = try meeting.status
guard status == .recorded || status == .failed || status == .completed else {
    throw TranscriptionServiceError.meetingNotTranscribable
}
```

- [ ] **Step 7: Run the focused tests to verify they pass**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcription-rerun "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS for the new eligibility and retranscription tests, with existing focused tests still green.

- [ ] **Step 8: Commit the domain-eligibility changes**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/Services/Transcription/TranscriptionService.swift QuickMeetingTests/AppViewModelTests.swift QuickMeetingTests/TranscriptionServiceTests.swift
git commit -m "feat: allow retranscription of completed meetings"
```

### Task 2: Reset transcript metadata when transcription starts

**Files:**
- Modify: `QuickMeetingTests/MeetingStoreTests.swift`
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`
- Modify: `QuickMeeting/Services/MeetingStore.swift`
- Modify: `QuickMeeting/Models/Meeting.swift`

- [ ] **Step 1: Write the failing `MeetingStore` reset test**

Add a new test near the existing transcription lifecycle tests:

```swift
@Test
func startTranscriptionClearsExistingTranscriptMetadata() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.createCompletedMeeting(
        transcriptFileName: "transcript.txt",
        transcriptPreview: "Existing transcript"
    )
    let updatedAt = Date(timeIntervalSince1970: 1_234_568_250)

    try harness.store.startTranscription(meetingID: meeting.id, updatedAt: updatedAt)

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .transcribing)
    #expect(reloaded.transcriptFilePath == nil)
    #expect(reloaded.transcriptPreview == nil)
    #expect(reloaded.updatedAt == updatedAt)
}
```

- [ ] **Step 2: Run the focused `MeetingStore` test to confirm it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcription-rerun "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingStoreTests
```

Expected: FAIL because `startTranscription(meetingID:updatedAt:)` currently preserves transcript metadata.

- [ ] **Step 3: Add a `TranscriptionService` regression test for pre-start validation**

Add this test next to the model/audio validation tests:

```swift
@Test
func transcribeCompletedMeetingWithMissingModelDoesNotClearExistingTranscript() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createCompletedMeeting(
        transcriptText: "Existing transcript",
        preview: "Existing transcript"
    )

    await #expect(throws: TranscriptionServiceError.noInstalledDefaultModel) {
        try await harness.service.transcribe(meetingID: meeting.id)
    }

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .completed)
    #expect(reloaded.transcriptPreview == "Existing transcript")
    #expect(reloaded.transcriptFilePath != nil)
}
```

- [ ] **Step 4: Run the focused `TranscriptionService` test to confirm current behavior is protected**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcription-rerun "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: The new validation test should already pass or fail only if the setup helper is incomplete. Keep it in place before changing persistence so pre-start behavior stays guarded.

- [ ] **Step 5: Update `Meeting` so beginning transcription clears transcript metadata**

Change `QuickMeeting/Models/Meeting.swift`:

```swift
func beginTranscription(updatedAt: Date = Date()) {
    transcriptFilePath = nil
    transcriptPreview = nil
    statusRawValue = MeetingStatus.transcribing.rawValue
    touch(updatedAt: updatedAt)
}
```

- [ ] **Step 6: Keep `MeetingStore.startTranscription` routing through the reset-aware meeting method**

Confirm `QuickMeeting/Services/MeetingStore.swift` stays focused:

```swift
func startTranscription(meetingID: UUID, updatedAt: Date) throws {
    let meeting = try fetchMeeting(id: meetingID)
    meeting.beginTranscription(updatedAt: updatedAt)
    try modelContext.save()
}
```

If any direct field edits were introduced during development, remove them so `MeetingStore` keeps the single persistence transition.

- [ ] **Step 7: Add helper constructors in tests for completed meetings with transcript data**

In `QuickMeetingTests/MeetingStoreTests.swift`, extend the harness:

```swift
func createCompletedMeeting(
    transcriptFileName: String,
    transcriptPreview: String
) throws -> Meeting {
    let meeting = try createRecordedMeeting()
    let transcriptURL = folderURL(for: meeting.id).appendingPathComponent(transcriptFileName)
    try store.completeTranscription(
        meetingID: meeting.id,
        transcriptFileURL: transcriptURL,
        transcriptPreview: transcriptPreview,
        updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
    )
    return try reloadMeeting(id: meeting.id)
}
```

In `QuickMeetingTests/TranscriptionServiceTests.swift`, extend the harness:

```swift
func createCompletedMeeting(
    transcriptText: String,
    preview: String
) throws -> Meeting {
    let meeting = try createRecordedMeeting()
    let transcriptURL = meetingFileStore.rootURL
        .appendingPathComponent(meeting.id.uuidString, isDirectory: true)
        .appendingPathComponent("transcript.txt")
    try transcriptText.write(to: transcriptURL, atomically: true, encoding: .utf8)
    try meetingStore.completeTranscription(
        meetingID: meeting.id,
        transcriptFileURL: transcriptURL,
        transcriptPreview: preview,
        updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
    )
    return try reloadMeeting(id: meeting.id)
}
```

- [ ] **Step 8: Run the focused persistence and service tests to verify they pass**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcription-rerun "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS for the new metadata-reset test, the completed-meeting retranscription test, and the validation guard test.

- [ ] **Step 9: Commit the persistence reset changes**

```bash
git add QuickMeeting/Models/Meeting.swift QuickMeeting/Services/MeetingStore.swift QuickMeetingTests/MeetingStoreTests.swift QuickMeetingTests/TranscriptionServiceTests.swift
git commit -m "feat: clear transcripts when retranscription starts"
```

### Task 3: Add the overwrite warning in meeting detail

**Files:**
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeeting/ContentView.swift`

- [ ] **Step 1: Add view state for the rerun confirmation alert**

In `QuickMeeting/Views/MeetingDetailView.swift`, add local state near the delete alert state:

```swift
@State private var isShowingDeleteConfirmation = false
@State private var isShowingRetranscriptionConfirmation = false
```

- [ ] **Step 2: Route the `Transcribe` action through a helper**

Add a small helper in `MeetingDetailView`:

```swift
private func handleTranscribeAction() {
    if shouldConfirmRetranscription {
        isShowingRetranscriptionConfirmation = true
    } else {
        onTranscribe()
    }
}

private var shouldConfirmRetranscription: Bool {
    guard let status = try? meeting.status else {
        return false
    }

    return status == .completed
}
```

- [ ] **Step 3: Update every `Transcribe` button to use the helper**

Replace each direct button action in `MeetingDetailView`:

```swift
Button("Transcribe", action: handleTranscribeAction)
    .buttonStyle(.borderedProminent)
    .disabled(!canTranscribe)
```

Apply this in:

- `transcriptEmptyState`
- `transcriptUnavailableState(message:)`
- `actionSection`

- [ ] **Step 4: Add the retranscription confirmation alert**

Attach a second `.alert` to `MeetingDetailView`:

```swift
.alert(
    "Replace Transcript?",
    isPresented: $isShowingRetranscriptionConfirmation
) {
    Button("Replace", role: .destructive) {
        onTranscribe()
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("Starting transcription again will overwrite the existing transcript for this meeting.")
}
```

Keep the existing delete alert unchanged.

- [ ] **Step 5: Verify `ContentView` wiring needs no structural change**

Keep the existing `MeetingDetailView` closure in `QuickMeeting/ContentView.swift`:

```swift
onTranscribe: {
    Task {
        await appViewModel.transcribeMeeting(selectedMeeting)
    }
}
```

No rerun-specific closure is needed because `MeetingDetailView` now decides whether confirmation is required.

- [ ] **Step 6: Build and run the focused app-level tests**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcription-rerun "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS. There may be no automated SwiftUI interaction test for the alert itself, so rely on manual verification for the confirmation flow.

- [ ] **Step 7: Manually verify the rerun UX in the app**

Check these behaviors in a local run:

- a completed meeting shows its current transcript
- clicking `Transcribe` shows the overwrite warning
- clicking `Cancel` leaves the transcript visible
- clicking `Replace` clears the transcript and shows the progress UI
- a successful rerun shows the new transcript
- a failed rerun leaves the meeting in `failed` with no transcript visible

If needed, use a temporarily forced backend failure after verifying the success path so both outcomes are exercised.

- [ ] **Step 8: Commit the meeting-detail confirmation flow**

```bash
git add QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/ContentView.swift
git commit -m "feat: confirm transcript overwrite before rerun"
```

### Task 4: Final verification and cleanup

**Files:**
- Modify: `docs/plans/2026-05-06-transcription-rerun.md`

- [ ] **Step 1: Run the full focused regression suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcription-rerun "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: PASS for retranscription eligibility, persistence reset, service orchestration, and transcript-content behavior.

- [ ] **Step 2: Review the final diff for accidental scope creep**

Run:

```bash
git diff --stat HEAD~3..HEAD
```

Expected: only the rerun-related view, model, service, and test files changed. If extra files appear, inspect them and either justify them or remove unrelated edits before shipping.

- [ ] **Step 3: Update this plan with verification notes if execution uncovered anything surprising**

Append a short note under this task only if execution diverges from the plan, for example:

```markdown
Execution note: `MeetingDetailView` needed no `ContentView` changes beyond closure reuse because the confirmation logic stayed local to the detail view.
```

If execution matches the plan, do not edit the plan further.

- [ ] **Step 4: Create the final implementation commit if you have not already squashed work into coherent checkpoints**

```bash
git status --short
```

Expected: clean working tree. If not clean and the remaining changes are intentional, stage them with `git add` and create one final commit message that reflects the last uncommitted rerun work.

## Self-Review

- Spec coverage: the plan covers completed-meeting eligibility, confirmation UI, destructive reset timing, validation-before-clear behavior, success replacement, and failed-empty outcomes.
- Placeholder scan: removed vague instructions and replaced them with concrete test code, file paths, and commands.
- Type consistency: the plan consistently uses `canTranscribeMeeting`, `transcribe(meetingID:)`, `startTranscription(meetingID:updatedAt:)`, `beginTranscription(updatedAt:)`, `isShowingRetranscriptionConfirmation`, and `handleTranscribeAction()`.
