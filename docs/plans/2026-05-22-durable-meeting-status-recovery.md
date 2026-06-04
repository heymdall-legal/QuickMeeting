**Goal:** Make persisted meeting status crash-safe by removing transient `recording` and `transcribing` states from SwiftData, repairing legacy rows deterministically, and keeping active recording/transcription indicators runtime-only.

**Architecture:** Keep `Meeting.statusRawValue` as a persisted string, but narrow `MeetingStatus` to durable states only and add a single recovery path in `MeetingStore` that normalizes legacy raw values before callers use a meeting. Leave active recording in `AppViewModel.recordingState` and active transcription in `TranscriptionProgressCenter` plus `TranscriptionService`, then update status presentation helpers to depend on runtime progress instead of persisted transient enum cases.

**Tech Stack:** Swift, SwiftData, Swift Testing, SwiftUI, xcodebuild

---

### Task 1: Narrow The Persisted Status Model

**Files:**
- Modify: `QuickMeeting/Models/MeetingStatus.swift`
- Modify: `QuickMeeting/Models/Meeting.swift`
- Test: `QuickMeetingTests/MeetingStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Add these tests in `QuickMeetingTests/MeetingStoreTests.swift`:

```swift
@Test
func createMeetingPersistsFailedUntilRecordingFinishes() throws {
    let harness = try MeetingStoreHarness()
    let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
    let folderURL = URL(fileURLWithPath: "/tmp/meeting-\(UUID().uuidString)")
    let audioFileURL = folderURL.appendingPathComponent("audio.wav")

    let meeting = try harness.store.createMeeting(
        title: "Design Review",
        startedAt: startedAt,
        folderURL: folderURL,
        audioFileURL: audioFileURL
    )

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .failed)
    #expect(reloaded.endedAt == nil)
    #expect(reloaded.duration == nil)
}

@Test
func startTranscriptionClearsTranscriptMetadataWithoutPersistingTransientStatus() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.createCompletedMeeting(
        transcript: StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Existing transcript", speakerID: "speaker-1")]
        ),
        transcriptPreview: "Existing transcript"
    )

    try harness.store.startTranscription(
        meetingID: meeting.id,
        updatedAt: Date(timeIntervalSince1970: 1_234_568_250)
    )

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .recorded)
    #expect(reloaded.transcriptPreview == nil)
    #expect(reloaded.transcriptSpeakers.isEmpty)
    #expect(reloaded.transcriptSegments.isEmpty)
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests
```

Expected: FAIL because `createMeeting` still persists `.recording` and `beginTranscription()` still persists `.transcribing`.

- [ ] **Step 3: Write the minimal model changes**

Update `QuickMeeting/Models/MeetingStatus.swift` to durable-only cases:

```swift
enum MeetingStatus: String, Codable, CaseIterable, Sendable {
    case recorded
    case completed
    case failed
}
```

Update `QuickMeeting/Models/Meeting.swift` so creation and re-transcription stay durable:

```swift
func finishRecording(endedAt: Date, duration: TimeInterval, updatedAt: Date = Date()) {
    self.endedAt = endedAt
    self.duration = duration
    statusRawValue = MeetingStatus.recorded.rawValue
    touch(updatedAt: updatedAt)
}

func beginTranscription(updatedAt: Date = Date()) {
    transcriptFilePath = nil
    transcriptPreview = nil
    transcriptSpeakers.removeAll()
    transcriptSegments.removeAll()
    statusRawValue = MeetingStatus.recorded.rawValue
    touch(updatedAt: updatedAt)
}
```

Update `QuickMeeting/Services/MeetingStore.swift` creation path:

```swift
let meeting = Meeting(
    id: id,
    title: title,
    startedAt: startedAt,
    status: .failed,
    audioFilePath: normalizedAudioFileURL.path(percentEncoded: false),
    attendeeNames: attendeeNames,
    createdAt: now,
    updatedAt: now
)
```

- [ ] **Step 4: Run the focused tests to verify they pass**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests
```

Expected: PASS for the new assertions and existing recording-finish/completion/failure behavior.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Models/MeetingStatus.swift QuickMeeting/Models/Meeting.swift QuickMeeting/Services/MeetingStore.swift QuickMeetingTests/MeetingStoreTests.swift
git commit -m "refactor: persist only durable meeting statuses"
```

### Task 2: Add Legacy Status Recovery In MeetingStore

**Files:**
- Modify: `QuickMeeting/Services/MeetingStore.swift`
- Test: `QuickMeetingTests/MeetingStoreTests.swift`

- [ ] **Step 1: Write the failing recovery tests**

Add these tests in `QuickMeetingTests/MeetingStoreTests.swift`:

```swift
@Test
func fetchMeetingRepairsLegacyRecordingToRecordedWhenAudioFileExistsAndIsNonEmpty() throws {
    let harness = try MeetingStoreHarness()
    let fileURL = harness.fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("audio.wav")
    try harness.fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    #expect(harness.fileManager.createFile(atPath: fileURL.path, contents: Data([1])))

    let meeting = try harness.insertMeeting(statusRawValue: "recording", audioFilePath: fileURL.path)

    let repaired = try harness.store.fetchMeeting(id: meeting.id)
    #expect(try repaired.status == .recorded)
    #expect(try harness.reloadMeeting(id: meeting.id).status == .recorded)
}

@Test
func fetchMeetingRepairsLegacyRecordingToFailedWhenAudioFileIsMissingOrEmpty() throws {
    let harness = try MeetingStoreHarness()
    let missingMeeting = try harness.insertMeeting(
        statusRawValue: "recording",
        audioFilePath: "/tmp/\(UUID().uuidString)/missing.wav"
    )

    let emptyFolderURL = harness.fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try harness.fileManager.createDirectory(at: emptyFolderURL, withIntermediateDirectories: true)
    let emptyFileURL = emptyFolderURL.appendingPathComponent("audio.wav")
    #expect(harness.fileManager.createFile(atPath: emptyFileURL.path, contents: Data()))
    let emptyMeeting = try harness.insertMeeting(statusRawValue: "recording", audioFilePath: emptyFileURL.path)

    #expect(try harness.store.fetchMeeting(id: missingMeeting.id).status == .failed)
    #expect(try harness.store.fetchMeeting(id: emptyMeeting.id).status == .failed)
}

@Test
func fetchMeetingRepairsLegacyTranscribingToRecorded() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.insertMeeting(
        statusRawValue: "transcribing",
        audioFilePath: "/tmp/\(UUID().uuidString)/audio.wav"
    )

    let repaired = try harness.store.fetchMeeting(id: meeting.id)
    #expect(try repaired.status == .recorded)
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests
```

Expected: FAIL because `Meeting.status` still throws on legacy raw values and `MeetingStore.fetchMeeting` does not repair them.

- [ ] **Step 3: Implement the recovery path in the store**

Add a recovery helper in `QuickMeeting/Services/MeetingStore.swift` along these lines:

```swift
func fetchMeeting(id: UUID) throws -> Meeting {
    let descriptor = FetchDescriptor<Meeting>(
        predicate: #Predicate { meeting in
            meeting.id == id
        }
    )

    guard let meeting = try modelContext.fetch(descriptor).first else {
        throw MeetingStoreError.meetingNotFound
    }

    try repairLegacyStatusIfNeeded(for: meeting, updatedAt: Date())
    return meeting
}

private func repairLegacyStatusIfNeeded(for meeting: Meeting, updatedAt: Date) throws {
    switch meeting.legacyStatusRawValue {
    case MeetingStatus.recorded.rawValue, MeetingStatus.completed.rawValue, MeetingStatus.failed.rawValue:
        return
    case "recording":
        let repairedStatus = resolvedRecoveredRecordingStatus(audioFilePath: meeting.audioFilePath)
        meeting.setStatus(repairedStatus, updatedAt: updatedAt)
        try modelContext.save()
    case "transcribing":
        meeting.setStatus(.recorded, updatedAt: updatedAt)
        try modelContext.save()
    case let rawValue:
        throw MeetingError.invalidStatusRawValue(rawValue)
    }
}
```

Expose the raw string inside `QuickMeeting/Models/Meeting.swift` for store-only recovery:

```swift
var legacyStatusRawValue: String {
    statusRawValue
}
```

Add a file-size helper in `QuickMeeting/Services/MeetingStore.swift`:

```swift
private func resolvedRecoveredRecordingStatus(audioFilePath: String) -> MeetingStatus {
    let fileURL = URL(fileURLWithPath: audioFilePath)
    guard
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
        let fileSize = values.fileSize,
        fileSize > 0
    else {
        return .failed
    }

    return .recorded
}
```

Extend `MeetingStoreHarness` to support direct legacy-row insertion:

```swift
let fileManager = FileManager.default

func insertMeeting(statusRawValue: String, audioFilePath: String) throws -> Meeting {
    let meeting = Meeting(
        title: "Recovered Meeting",
        startedAt: Date(timeIntervalSince1970: 1_234_567_890),
        status: .failed,
        audioFilePath: audioFilePath
    )
    meeting.setLegacyStatusRawValue(statusRawValue)
    store.modelContext.insert(meeting)
    try store.modelContext.save()
    return meeting
}
```

Also add the model test seam needed by the harness:

```swift
func setLegacyStatusRawValue(_ rawValue: String) {
    statusRawValue = rawValue
}
```

- [ ] **Step 4: Run the focused tests to verify they pass**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests
```

Expected: PASS with legacy `recording` and `transcribing` rows normalized on fetch.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Models/Meeting.swift QuickMeeting/Services/MeetingStore.swift QuickMeetingTests/MeetingStoreTests.swift
git commit -m "feat: repair legacy transient meeting statuses"
```

### Task 3: Update Runtime And Service Logic To Ignore Persisted Transient States

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/Services/Transcription/TranscriptionService.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`
- Test: `QuickMeetingTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing runtime and service tests**

Update `QuickMeetingTests/AppViewModelTests.swift`:

```swift
@Test
func stopRecordingFailureKeepsPersistedMeetingDurableWhileRuntimeStateRemainsRecoverable() async throws {
    let harness = try AppViewModelTestHarness(stopResult: .failure(StopRecordingTestError.stopFailed))
    let viewModel = AppViewModel(
        meetingStore: harness.meetingStore,
        meetingFileStore: harness.meetingFileStore,
        recordingService: harness.recordingService,
        recordingPermissions: harness.recordingPermissions
    )

    await viewModel.startRecording()
    await viewModel.stopRecording()

    let persistedMeeting = try #require(try harness.context.fetch(FetchDescriptor<Meeting>()).first)
    #expect(try persistedMeeting.status == .failed)
    #expect(viewModel.canStopRecording)
}
```

Update `QuickMeetingTests/TranscriptionServiceTests.swift`:

```swift
@Test
func transcribeFailureLeavesMeetingDurableAndRetryable() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createRecordedMeeting()
    await harness.installDefaultModel(.small)
    await harness.backend.setResult(.failure(TestTranscriptionError.failed))

    await #expect(throws: TestTranscriptionError.failed) {
        try await harness.service.transcribe(meetingID: meeting.id)
    }

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .failed)
}

@Test
func transcribeCompletedMeetingRemainsEligibleForRetranscriptionWithoutTransientStatus() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createCompletedMeeting(
        transcript: StoredTranscript(speakers: [], segments: []),
        preview: "Old transcript"
    )

    await harness.installDefaultModel(.small)
    await harness.backend.setResult(.success(TranscriptionResult(fullText: "Done", segments: [])))
    await harness.diarizer.setResult(.success(StoredTranscript(speakers: [], segments: [])))

    try await harness.service.transcribe(meetingID: meeting.id)

    #expect(try harness.reloadMeeting(id: meeting.id).status == .completed)
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: FAIL where tests still assume persisted `.recording` or `.transcribing` semantics.

- [ ] **Step 3: Implement the minimal runtime/service changes**

Update `QuickMeeting/ViewModels/AppViewModel.swift` so durable state and runtime state are clearly separated:

```swift
func canTranscribeMeeting(_ meeting: Meeting) -> Bool {
    guard let status = try? meeting.status else {
        return false
    }

    return status == .recorded || status == .failed || status == .completed
}
```

Keep `recoverableRecordingMeetingID` behavior unchanged so stop failures are still recoverable in-memory, but do not rely on persisted `.recording` anywhere in the view model tests.

Keep `QuickMeeting/Services/Transcription/TranscriptionService.swift` status gate durable-only:

```swift
let status = try meeting.status
guard status == .recorded || status == .failed || status == .completed else {
    throw TranscriptionServiceError.meetingNotTranscribable
}
```

Do not add any new persisted transient status writes during transcription start.

- [ ] **Step 4: Run the focused tests to verify they pass**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS with runtime recovery behavior intact and durable persisted states only.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/Services/Transcription/TranscriptionService.swift QuickMeetingTests/AppViewModelTests.swift QuickMeetingTests/TranscriptionServiceTests.swift
git commit -m "refactor: separate runtime activity from meeting persistence"
```

### Task 4: Update Status Presentation Helpers And Meeting Detail UI

**Files:**
- Modify: `QuickMeeting/Support/MeetingTranscriptionProgressDisplay.swift`
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Test: `QuickMeetingTests/MeetingTranscriptionProgressDisplayTests.swift`

- [ ] **Step 1: Write the failing helper tests**

Update `QuickMeetingTests/MeetingTranscriptionProgressDisplayTests.swift`:

```swift
@Test
func progressPaneUsesRuntimeProgressWithoutPersistedTranscribingStatus() {
    let state = transcriptPaneState(
        hasTranscript: false,
        progress: 0.42,
        diarizationProgress: nil
    )

    #expect(state == .transcribing(progress: 0.42))
}

@Test
func diarizationPaneUsesRuntimeProgressWithoutPersistedTranscribingStatus() {
    let state = transcriptPaneState(
        hasTranscript: false,
        progress: nil,
        diarizationProgress: 0.6
    )

    #expect(state == .diarizing(progress: 0.6))
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptionProgressDisplayTests
```

Expected: FAIL because `transcriptPaneState` still requires `meetingStatus == .transcribing`.

- [ ] **Step 3: Implement the minimal helper and UI changes**

Update `QuickMeeting/Support/MeetingTranscriptionProgressDisplay.swift`:

```swift
func transcriptPaneState(
    hasTranscript: Bool,
    progress: Double?,
    diarizationProgress: Double?
) -> TranscriptPaneState {
    if let diarizationProgress {
        return .diarizing(progress: min(max(diarizationProgress, 0), 1))
    }

    if let progress {
        return .transcribing(progress: min(max(progress, 0), 1))
    }

    if hasTranscript {
        return .transcript
    }

    return .empty
}
```

Update `QuickMeeting/Views/MeetingDetailView.swift` call sites and status label:

```swift
private var currentTranscriptPaneState: TranscriptPaneState {
    transcriptPaneState(
        hasTranscript: meeting.storedTranscript != nil,
        progress: transcriptionProgress,
        diarizationProgress: diarizationProgress
    )
}

private var statusText: String {
    if diarizationProgress != nil || transcriptionProgress != nil {
        return "Transcribing"
    }

    guard let status = try? meeting.status else {
        return "Invalid Status"
    }

    switch status {
    case .recorded:
        return "Recorded"
    case .completed:
        return "Completed"
    case .failed:
        return "Failed"
    }
}
```

- [ ] **Step 4: Run the focused tests to verify they pass**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptionProgressDisplayTests
```

Expected: PASS with progress UI driven entirely by runtime state.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Support/MeetingTranscriptionProgressDisplay.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeetingTests/MeetingTranscriptionProgressDisplayTests.swift
git commit -m "refactor: drive transcript progress UI from runtime state"
```

### Task 5: Run Focused Regression Coverage

**Files:**
- Modify: `QuickMeetingTests/MeetingStoreTests.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`
- Modify: `QuickMeetingTests/MeetingTranscriptionProgressDisplayTests.swift`

- [ ] **Step 1: Run the persistence-focused suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests
```

Expected: PASS.

- [ ] **Step 2: Run the runtime recording/transcription suites**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/MeetingTranscriptionProgressDisplayTests
```

Expected: PASS.

- [ ] **Step 3: Run the broader approved regression slice**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingFileStoreTests -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS with no regressions in artifact handling, durable status persistence, or recording lifecycle behavior.

- [ ] **Step 4: Commit final verification-only adjustments if any test code changed**

```bash
git add QuickMeetingTests/MeetingStoreTests.swift QuickMeetingTests/AppViewModelTests.swift QuickMeetingTests/TranscriptionServiceTests.swift QuickMeetingTests/MeetingTranscriptionProgressDisplayTests.swift
git commit -m "test: cover durable meeting status recovery"
```
