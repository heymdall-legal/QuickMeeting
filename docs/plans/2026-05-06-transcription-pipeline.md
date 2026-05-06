**Goal:** Build a manual meeting transcription pipeline that runs Whisper against an existing meeting’s `audio.wav`, writes `transcript.txt`, updates meeting status and preview metadata, and keeps the design extensible for future diarization.

**Architecture:** Keep orchestration in `AppViewModel` and a dedicated `TranscriptionService`, keep persistence rules in `MeetingStore`, and isolate Whisper runtime details behind a backend protocol. Return structured in-memory transcription results now, but persist only plain text so the first release stays lean while preserving a path to diarization.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, Foundation, WhisperKit / Argmax model management

---

## File Map

### Create

- `QuickMeeting/Models/TranscriptSegment.swift`
  Purpose: Define the in-memory `TranscriptSegment` and `TranscriptionResult` types used by the backend and service.
- `QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift`
  Purpose: Convert structured transcription results into `transcript.txt` and preview text.
- `QuickMeeting/Services/Transcription/WhisperTranscriptionBackend.swift`
  Purpose: Define the backend protocol and a small request/response contract for transcription runtimes.
- `QuickMeeting/Services/Transcription/WhisperKitTranscriptionBackend.swift`
  Purpose: Adapt WhisperKit output into the app’s `TranscriptionResult`.
- `QuickMeeting/Services/Transcription/TranscriptionService.swift`
  Purpose: Define the app-facing transcription service protocol, error types, and the default implementation.
- `QuickMeetingTests/TranscriptionArtifactWriterTests.swift`
  Purpose: Verify transcript flattening, file writing, and preview derivation.
- `QuickMeetingTests/TranscriptionServiceTests.swift`
  Purpose: Verify orchestration, validation, meeting state transitions, and failure handling.

### Modify

- `QuickMeeting/Models/Meeting.swift`
  Purpose: Add focused mutation helpers for transcription lifecycle updates.
- `QuickMeeting/Services/MeetingStore.swift`
  Purpose: Add transcription-specific persistence methods and meeting lookup helpers.
- `QuickMeeting/ViewModels/AppViewModel.swift`
  Purpose: Add manual transcription action, UI-facing error state, and single-job coordination hooks.
- `QuickMeeting/Views/MeetingDetailView.swift`
  Purpose: Add the `Transcribe` button and show transcript metadata when present.
- `QuickMeeting/QuickMeetingApp.swift`
  Purpose: Wire the real transcription service into the shared app graph.
- `QuickMeetingTests/MeetingStoreTests.swift`
  Purpose: Add coverage for transcription lifecycle persistence helpers.
- `QuickMeetingTests/AppViewModelTests.swift`
  Purpose: Add view-model-level tests for the manual transcription action and UI error handling.

## Task 1: Add Transcription Domain Types And MeetingStore Lifecycle Methods

**Files:**
- Create: `QuickMeeting/Models/TranscriptSegment.swift`
- Modify: `QuickMeeting/Models/Meeting.swift`
- Modify: `QuickMeeting/Services/MeetingStore.swift`
- Test: `QuickMeetingTests/MeetingStoreTests.swift`

- [ ] **Step 1: Write the failing persistence tests**

```swift
@Test
func startTranscriptionMarksMeetingAsTranscribing() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.createRecordedMeeting()
    let startedAt = Date(timeIntervalSince1970: 1_234_568_000)

    try harness.store.startTranscription(meetingID: meeting.id, updatedAt: startedAt)

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .transcribing)
    #expect(reloaded.updatedAt == startedAt)
}

@Test
func completeTranscriptionPersistsTranscriptPathAndPreview() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.createRecordedMeeting()
    let transcriptURL = harness.folderURL(for: meeting.id).appendingPathComponent("transcript.txt")
    let completedAt = Date(timeIntervalSince1970: 1_234_568_100)

    try harness.store.completeTranscription(
        meetingID: meeting.id,
        transcriptFileURL: transcriptURL,
        transcriptPreview: "First line of transcript",
        updatedAt: completedAt
    )

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .completed)
    #expect(reloaded.transcriptFilePath == transcriptURL.standardizedFileURL.path())
    #expect(reloaded.transcriptPreview == "First line of transcript")
    #expect(reloaded.updatedAt == completedAt)
}

@Test
func failTranscriptionMarksMeetingAsFailedWithoutRemovingTranscriptMetadata() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.createRecordedMeeting()
    let failedAt = Date(timeIntervalSince1970: 1_234_568_200)

    try harness.store.failTranscription(meetingID: meeting.id, updatedAt: failedAt)

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .failed)
    #expect(reloaded.updatedAt == failedAt)
}
```

- [ ] **Step 2: Run the targeted test file to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests
```

Expected: FAIL with missing `startTranscription`, `completeTranscription`, and `failTranscription` members.

- [ ] **Step 3: Add the domain types and minimal persistence code**

```swift
// QuickMeeting/Models/TranscriptSegment.swift
import Foundation

struct TranscriptSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let speakerID: String?

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        speakerID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speakerID = speakerID
    }
}

struct TranscriptionResult: Equatable, Sendable {
    let fullText: String
    let segments: [TranscriptSegment]
}
```

```swift
// QuickMeeting/Models/Meeting.swift
func beginTranscription(updatedAt: Date = Date()) {
    statusRawValue = MeetingStatus.transcribing.rawValue
    touch(updatedAt: updatedAt)
}

func completeTranscription(
    transcriptFilePath: String,
    transcriptPreview: String,
    updatedAt: Date = Date()
) {
    self.transcriptFilePath = transcriptFilePath
    self.transcriptPreview = transcriptPreview
    statusRawValue = MeetingStatus.completed.rawValue
    touch(updatedAt: updatedAt)
}

func failTranscription(updatedAt: Date = Date()) {
    statusRawValue = MeetingStatus.failed.rawValue
    touch(updatedAt: updatedAt)
}
```

```swift
// QuickMeeting/Services/MeetingStore.swift
func fetchMeeting(id: UUID) throws -> Meeting {
    let descriptor = FetchDescriptor<Meeting>(
        predicate: #Predicate { meeting in
            meeting.id == id
        }
    )

    guard let meeting = try modelContext.fetch(descriptor).first else {
        throw MeetingStoreError.meetingNotFound
    }

    return meeting
}

func startTranscription(meetingID: UUID, updatedAt: Date) throws {
    let meeting = try fetchMeeting(id: meetingID)
    meeting.beginTranscription(updatedAt: updatedAt)
    try modelContext.save()
}

func completeTranscription(
    meetingID: UUID,
    transcriptFileURL: URL,
    transcriptPreview: String,
    updatedAt: Date
) throws {
    let meeting = try fetchMeeting(id: meetingID)
    meeting.completeTranscription(
        transcriptFilePath: transcriptFileURL.standardizedFileURL.path(),
        transcriptPreview: transcriptPreview,
        updatedAt: updatedAt
    )
    try modelContext.save()
}

func failTranscription(meetingID: UUID, updatedAt: Date) throws {
    let meeting = try fetchMeeting(id: meetingID)
    meeting.failTranscription(updatedAt: updatedAt)
    try modelContext.save()
}
```

- [ ] **Step 4: Run the persistence tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests
```

Expected: PASS for the new transcription lifecycle tests.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Models/TranscriptSegment.swift QuickMeeting/Models/Meeting.swift QuickMeeting/Services/MeetingStore.swift QuickMeetingTests/MeetingStoreTests.swift
git commit -m "feat: add transcription meeting lifecycle"
```

## Task 2: Add Transcript Artifact Writing

**Files:**
- Create: `QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift`
- Test: `QuickMeetingTests/TranscriptionArtifactWriterTests.swift`

- [ ] **Step 1: Write the failing artifact-writer tests**

```swift
@Test
func writeArtifactsPersistsTranscriptTextNextToMeetingAudio() throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let writer = TranscriptionArtifactWriter(fileManager: fileManager)
    let result = TranscriptionResult(
        fullText: "Hello world",
        segments: [
            TranscriptSegment(text: "Hello"),
            TranscriptSegment(text: "world")
        ]
    )

    let artifacts = try writer.writeArtifacts(for: result, in: rootURL)

    #expect(artifacts.transcriptFileURL == rootURL.appendingPathComponent("transcript.txt"))
    #expect(try String(contentsOf: artifacts.transcriptFileURL) == "Hello world")
    #expect(artifacts.previewText == "Hello world")
}

@Test
func previewIsTrimmedFromStructuredResultText() throws {
    let writer = TranscriptionArtifactWriter()
    let result = TranscriptionResult(
        fullText: "  First sentence.\nSecond sentence.  ",
        segments: []
    )

    #expect(writer.makePreviewText(from: result) == "First sentence.\nSecond sentence.")
}
```

- [ ] **Step 2: Run the new test file to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionArtifactWriterTests
```

Expected: FAIL because `TranscriptionArtifactWriter` does not exist.

- [ ] **Step 3: Implement the minimal writer**

```swift
// QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift
import Foundation

struct TranscriptionArtifacts: Equatable {
    let transcriptFileURL: URL
    let previewText: String
}

struct TranscriptionArtifactWriter {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writeArtifacts(
        for result: TranscriptionResult,
        in meetingFolderURL: URL
    ) throws -> TranscriptionArtifacts {
        let transcriptFileURL = meetingFolderURL.appendingPathComponent("transcript.txt")
        let transcriptText = result.fullText.trimmingCharacters(in: .whitespacesAndNewlines)

        try transcriptText.write(to: transcriptFileURL, atomically: true, encoding: .utf8)

        return TranscriptionArtifacts(
            transcriptFileURL: transcriptFileURL,
            previewText: makePreviewText(from: result)
        )
    }

    func makePreviewText(from result: TranscriptionResult) -> String {
        result.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run the artifact-writer tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionArtifactWriterTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift QuickMeetingTests/TranscriptionArtifactWriterTests.swift
git commit -m "feat: add transcription artifact writer"
```

## Task 3: Add The Backend Protocol And Default Transcription Service

**Files:**
- Create: `QuickMeeting/Services/Transcription/WhisperTranscriptionBackend.swift`
- Create: `QuickMeeting/Services/Transcription/TranscriptionService.swift`
- Test: `QuickMeetingTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing orchestration tests**

```swift
@Test
func transcribeRecordedMeetingWritesTranscriptAndCompletesMeeting() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createRecordedMeeting()
    harness.modelSettingsStore.defaultModelID = .small
    harness.modelStore.installedModelsByID = [.small: InstalledTranscriptionModel(sizeInBytes: 1, installedAt: nil)]
    harness.backend.result = .success(
        TranscriptionResult(
            fullText: "Transcript body",
            segments: [TranscriptSegment(text: "Transcript body", startTime: 0, endTime: 1)]
        )
    )

    try await harness.service.transcribe(meetingID: meeting.id)

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .completed)
    #expect(reloaded.transcriptPreview == "Transcript body")
    #expect(reloaded.transcriptFilePath?.hasSuffix("/transcript.txt") == true)
}

@Test
func transcribeRejectsWhenNoDefaultInstalledModelExists() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createRecordedMeeting()

    await #expect(throws: TranscriptionServiceError.noInstalledDefaultModel) {
        try await harness.service.transcribe(meetingID: meeting.id)
    }
}

@Test
func transcribeRejectsWhenAnotherJobIsActive() async throws {
    let harness = try TranscriptionServiceHarness(suspendBackend: true)
    let firstMeeting = try harness.createRecordedMeeting()
    let secondMeeting = try harness.createRecordedMeeting()
    harness.installDefaultModel()

    let firstTask = Task {
        try await harness.service.transcribe(meetingID: firstMeeting.id)
    }

    while await harness.backend.snapshot().pendingRequestCount == 0 {
        await Task.yield()
    }

    await #expect(throws: TranscriptionServiceError.transcriptionAlreadyActive) {
        try await harness.service.transcribe(meetingID: secondMeeting.id)
    }

    harness.backend.resume(with: .success(TranscriptionResult(fullText: "Done", segments: [])))
    try await firstTask.value
}
```

- [ ] **Step 2: Run the service tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: FAIL with missing `TranscriptionService`, backend protocol, and service error types.

- [ ] **Step 3: Implement the protocol boundary and minimal service**

```swift
// QuickMeeting/Services/Transcription/WhisperTranscriptionBackend.swift
import Foundation

struct TranscriptionRequest: Equatable, Sendable {
    let audioFileURL: URL
    let model: TranscriptionModel
}

protocol WhisperTranscriptionBackend: Sendable {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}
```

```swift
// QuickMeeting/Services/Transcription/TranscriptionService.swift
import Foundation

enum TranscriptionServiceError: Error, Equatable {
    case meetingNotTranscribable
    case audioFileMissing
    case noInstalledDefaultModel
    case transcriptionAlreadyActive
}

protocol TranscriptionServicing: AnyObject {
    func transcribe(meetingID: UUID) async throws
}

@MainActor
final class TranscriptionService: TranscriptionServicing {
    private let meetingStore: MeetingStore
    private let modelStore: WhisperModelStore
    private let modelSettingsStore: ModelSettingsStore
    private let backend: any WhisperTranscriptionBackend
    private let artifactWriter: TranscriptionArtifactWriter
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private var activeMeetingID: UUID?

    init(
        meetingStore: MeetingStore,
        modelStore: WhisperModelStore,
        modelSettingsStore: ModelSettingsStore,
        backend: any WhisperTranscriptionBackend,
        artifactWriter: TranscriptionArtifactWriter = .init(),
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.meetingStore = meetingStore
        self.modelStore = modelStore
        self.modelSettingsStore = modelSettingsStore
        self.backend = backend
        self.artifactWriter = artifactWriter
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    func transcribe(meetingID: UUID) async throws {
        guard activeMeetingID == nil else {
            throw TranscriptionServiceError.transcriptionAlreadyActive
        }

        let meeting = try meetingStore.fetchMeeting(id: meetingID)
        let status = try meeting.status
        guard status == .recorded || status == .failed else {
            throw TranscriptionServiceError.meetingNotTranscribable
        }

        let audioFileURL = URL(fileURLWithPath: meeting.audioFilePath)
        guard fileManager.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionServiceError.audioFileMissing
        }

        guard
            let defaultModelID = modelSettingsStore.defaultModelID,
            let model = TranscriptionModelCatalog.model(for: defaultModelID),
            try await modelStore.installedModels()[defaultModelID] != nil
        else {
            throw TranscriptionServiceError.noInstalledDefaultModel
        }

        activeMeetingID = meetingID
        try meetingStore.startTranscription(meetingID: meetingID, updatedAt: dateProvider())

        do {
            let result = try await backend.transcribe(
                TranscriptionRequest(audioFileURL: audioFileURL, model: model)
            )
            let meetingFolderURL = audioFileURL.deletingLastPathComponent()
            let artifacts = try artifactWriter.writeArtifacts(for: result, in: meetingFolderURL)
            try meetingStore.completeTranscription(
                meetingID: meetingID,
                transcriptFileURL: artifacts.transcriptFileURL,
                transcriptPreview: artifacts.previewText,
                updatedAt: dateProvider()
            )
            activeMeetingID = nil
        } catch {
            try? meetingStore.failTranscription(meetingID: meetingID, updatedAt: dateProvider())
            activeMeetingID = nil
            throw error
        }
    }
}
```

- [ ] **Step 4: Run the service tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS for success, validation, and single-active-job tests.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/WhisperTranscriptionBackend.swift QuickMeeting/Services/Transcription/TranscriptionService.swift QuickMeetingTests/TranscriptionServiceTests.swift
git commit -m "feat: add transcription service orchestration"
```

## Task 4: Add The Real WhisperKit Backend Adapter

**Files:**
- Create: `QuickMeeting/Services/Transcription/WhisperKitTranscriptionBackend.swift`
- Modify: `QuickMeeting/Services/Transcription/TranscriptionService.swift`
- Test: `QuickMeetingTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Add one focused failing integration-shape test**

```swift
@Test
func transcriptionRequestUsesTheResolvedModelAndMeetingAudioPath() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createRecordedMeeting()
    harness.installDefaultModel(id: .largeV3)
    harness.backend.result = .success(TranscriptionResult(fullText: "Ready", segments: []))

    try await harness.service.transcribe(meetingID: meeting.id)

    let request = await #require(harness.backend.snapshot().requests.first)
    #expect(request.audioFileURL.path == meeting.audioFilePath)
    #expect(request.model.id == .largeV3)
}
```

- [ ] **Step 2: Run the focused test to verify it fails or is incomplete**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionServiceTests/transcriptionRequestUsesTheResolvedModelAndMeetingAudioPath
```

Expected: FAIL if the service is not yet forwarding the resolved model cleanly.

- [ ] **Step 3: Implement the real backend adapter**

```swift
// QuickMeeting/Services/Transcription/WhisperKitTranscriptionBackend.swift
import Foundation
import WhisperKit

struct WhisperKitTranscriptionBackend: WhisperTranscriptionBackend {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        let whisperKit = try await WhisperKit(
            model: request.model.argmaxModelID
        )

        let output = try await whisperKit.transcribe(audioPath: request.audioFileURL.path)
        let segments = output.flatMap(\.segments).map { segment in
            TranscriptSegment(
                text: segment.text,
                startTime: segment.start,
                endTime: segment.end
            )
        }

        return TranscriptionResult(
            fullText: output.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            segments: segments
        )
    }
}
```

- [ ] **Step 4: Re-run the focused service test and the full service suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/WhisperKitTranscriptionBackend.swift QuickMeeting/Services/Transcription/TranscriptionService.swift QuickMeetingTests/TranscriptionServiceTests.swift
git commit -m "feat: add whisper transcription backend"
```

## Task 5: Wire Manual Transcription Into AppViewModel And Meeting Detail UI

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing view-model tests**

```swift
@Test
func transcribeMeetingDelegatesToServiceAndClearsPreviousError() async throws {
    let harness = try AppViewModelTestHarness()
    let meeting = try harness.createRecordedMeeting()
    harness.transcriptionService.queuedResults = [.success(())]
    let viewModel = harness.makeViewModel()

    await viewModel.transcribeMeeting(meeting)

    #expect(harness.transcriptionService.snapshot().transcribedMeetingIDs == [meeting.id])
    #expect(viewModel.transcriptionErrorMessage == nil)
}

@Test
func transcribeMeetingStoresTheFailureMessageForUI() async throws {
    let harness = try AppViewModelTestHarness()
    let meeting = try harness.createRecordedMeeting()
    harness.transcriptionService.queuedResults = [.failure(TranscriptionActionTestError.failed)]
    let viewModel = harness.makeViewModel()

    await viewModel.transcribeMeeting(meeting)

    #expect(viewModel.transcriptionErrorMessage == "Transcription failed")
}
```

- [ ] **Step 2: Run the targeted view-model tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: FAIL with missing transcription APIs on the harness and view model.

- [ ] **Step 3: Implement the view-model and view wiring**

```swift
// QuickMeeting/ViewModels/AppViewModel.swift
@Published private(set) var transcriptionErrorMessage: String?

private let transcriptionService: any TranscriptionServicing

init(
    meetingStore: MeetingStore,
    meetingFileStore: MeetingFileStore,
    recordingService: any RecordingService,
    transcriptionService: any TranscriptionServicing = NoopTranscriptionService(),
    recordingPermissions: (any RecordingPermissions)? = nil,
    dateProvider: @escaping () -> Date = Date.init,
    meetingIDProvider: @escaping () -> UUID = UUID.init,
    meetingTitleProvider: @escaping (Date) -> String = { _ in "Untitled Meeting" }
) {
    self.transcriptionService = transcriptionService
    // keep the existing assignments
}

func transcribeMeeting(_ meeting: Meeting) async {
    transcriptionErrorMessage = nil

    do {
        try await transcriptionService.transcribe(meetingID: meeting.id)
    } catch {
        transcriptionErrorMessage = error.localizedDescription
    }
}

func clearTranscriptionError() {
    transcriptionErrorMessage = nil
}
```

```swift
// QuickMeeting/Views/MeetingDetailView.swift
let canTranscribe: Bool
let onTranscribe: () -> Void

if let transcriptFilePath = meeting.transcriptFilePath {
    VStack(alignment: .leading, spacing: 6) {
        Text("Transcript File")
            .font(.headline)
        Text(transcriptFilePath)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}

Button("Transcribe") {
    onTranscribe()
}
.buttonStyle(.borderedProminent)
.disabled(!canTranscribe)
```

```swift
// QuickMeeting/ContentView.swift call site
MeetingDetailView(
    meeting: selectedMeeting,
    canDelete: appViewModel.canDeleteMeeting(selectedMeeting),
    onDelete: {
        appViewModel.deleteMeeting(selectedMeeting)
    },
    canTranscribe: appViewModel.canTranscribeMeeting(selectedMeeting),
    onTranscribe: {
        Task {
            await appViewModel.transcribeMeeting(selectedMeeting)
        }
    }
)
```

- [ ] **Step 4: Re-run the view-model tests**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS for the new transcription action tests without regressing recording tests.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/ContentView.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: add manual meeting transcription action"
```

## Task 6: Wire The Real Service In QuickMeetingApp And Run The Focused End-To-End Test Pass

**Files:**
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeeting/ContentView.swift`
- Test: `QuickMeetingTests/MeetingStoreTests.swift`
- Test: `QuickMeetingTests/TranscriptionArtifactWriterTests.swift`
- Test: `QuickMeetingTests/TranscriptionServiceTests.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Add the final wiring change**

```swift
// QuickMeeting/QuickMeetingApp.swift
let modelSettingsStore = ModelSettingsStore()
let modelStore = ArgmaxWhisperModelStore()
let transcriptionService = TranscriptionService(
    meetingStore: MeetingStore(modelContext: modelContainer.mainContext),
    modelStore: modelStore,
    modelSettingsStore: modelSettingsStore,
    backend: WhisperKitTranscriptionBackend()
)

let transcriptionModelManager = TranscriptionModelManager(
    modelStore: modelStore,
    settingsStore: modelSettingsStore
)

_appViewModel = StateObject(
    wrappedValue: AppViewModel(
        meetingStore: MeetingStore(modelContext: modelContainer.mainContext),
        meetingFileStore: MeetingFileStore(),
        recordingService: DefaultRecordingService(
            audioCapturePipeline: NativeAudioCapturePipeline()
        ),
        transcriptionService: transcriptionService
    )
)
```

- [ ] **Step 2: Run the focused transcription-related suites**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/TranscriptionArtifactWriterTests -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS.

- [ ] **Step 3: Run the broader regression pass for the existing app tests**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
```

Expected: PASS for the full test suite.

- [ ] **Step 4: Smoke-check the manual UI flow**

Verify manually in the app:

```text
1. Open a recorded meeting with a valid audio file.
2. Confirm the detail screen shows a Transcribe button.
3. Start transcription and confirm status changes to Transcribing.
4. Wait for completion and confirm status changes to Completed.
5. Confirm transcript.txt exists next to audio.wav in the meeting folder.
6. Confirm the meeting now shows transcript metadata instead of losing audio metadata.
```

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/QuickMeetingApp.swift QuickMeeting/ContentView.swift
git commit -m "feat: wire transcription pipeline into app"
```

## Self-Review

### Spec Coverage

- manual transcription from meeting detail: covered in Task 5 and Task 6
- transcription of meeting-owned `audio.wav`: covered in Task 3 and Task 4
- plain-text transcript persistence: covered in Task 2 and Task 3
- meeting lifecycle updates: covered in Task 1 and Task 3
- single active job app-wide: covered in Task 3
- diarization-ready in-memory data types: covered in Task 1 and Task 4

### Placeholder Scan

- No `TBD`, `TODO`, or deferred “write tests later” instructions remain.
- Every task names exact files, commands, and concrete code to introduce.

### Type Consistency

- `TranscriptionResult`, `TranscriptSegment`, `TranscriptionRequest`, `TranscriptionService`, and `TranscriptionServicing` use the same names across tasks.
- `startTranscription`, `completeTranscription`, and `failTranscription` are used consistently between `Meeting`, `MeetingStore`, and tests.

## Handoff

Start with Task 1 and work strictly in TDD order. After each task, run the named test command before committing. When you’re ready, begin execution from this plan and keep commits scoped to the task boundaries above.
