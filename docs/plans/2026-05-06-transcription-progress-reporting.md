**Goal:** Add backend-driven transcription progress reporting that appears only in the active meeting detail screen while a meeting is being transcribed.

**Architecture:** Keep progress as transient runtime state in a dedicated `TranscriptionProgressCenter` rather than persisting percentages on `Meeting`. Extend the transcription backend contract to report normalized progress into `TranscriptionService`, then surface that live value through `AppViewModel` into `MeetingDetailView` with a small testable support helper for progress text and pane-state decisions.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, Foundation, WhisperKit

---

## File Map

### Create

- `QuickMeeting/Services/Transcription/TranscriptionProgressCenter.swift`
  Purpose: Store the active transcription progress value keyed by `meetingID` and expose observable reads for the UI.
- `QuickMeeting/Support/MeetingTranscriptionProgressDisplay.swift`
  Purpose: Centralize progress clamping, percent formatting, and pane-state decisions so UI behavior is easy to test.
- `QuickMeetingTests/TranscriptionProgressCenterTests.swift`
  Purpose: Verify progress registration, monotonic updates, clamping, and cleanup behavior.
- `QuickMeetingTests/MeetingTranscriptionProgressDisplayTests.swift`
  Purpose: Verify percent text and meeting-detail state selection without requiring SwiftUI inspection.

### Modify

- `QuickMeeting/Services/Transcription/WhisperTranscriptionBackend.swift`
  Purpose: Extend the request/response contract to carry progress updates.
- `QuickMeeting/Services/Transcription/WhisperKitTranscriptionBackend.swift`
  Purpose: Adapt WhisperKit runtime progress into normalized app progress updates.
- `QuickMeeting/Services/Transcription/TranscriptionService.swift`
  Purpose: Register, update, and clear transient progress while preserving existing transcription orchestration.
- `QuickMeeting/ViewModels/AppViewModel.swift`
  Purpose: Expose the progress center to the view layer and provide a per-meeting progress read helper.
- `QuickMeeting/Views/MeetingDetailView.swift`
  Purpose: Replace the empty transcript state with a dedicated transcribing progress UI when appropriate.
- `QuickMeeting/ContentView.swift`
  Purpose: Pass the active meeting progress value into `MeetingDetailView`.
- `QuickMeeting/QuickMeetingApp.swift`
  Purpose: Wire the shared `TranscriptionProgressCenter` into `TranscriptionService` and `AppViewModel`.
- `QuickMeetingTests/TranscriptionServiceTests.swift`
  Purpose: Add orchestration coverage for progress entry creation, updates, and cleanup.
- `QuickMeetingTests/AppViewModelTests.swift`
  Purpose: Verify the view model exposes progress for the selected meeting.

## Task 1: Add A Focused TranscriptionProgressCenter

**Files:**
- Create: `QuickMeeting/Services/Transcription/TranscriptionProgressCenter.swift`
- Test: `QuickMeetingTests/TranscriptionProgressCenterTests.swift`

- [ ] **Step 1: Write the failing progress-center tests**

```swift
import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct TranscriptionProgressCenterTests {
    @Test
    func startTrackingRegistersZeroProgress() {
        let meetingID = UUID()
        let center = TranscriptionProgressCenter()

        center.startTracking(meetingID: meetingID)

        #expect(center.progress(for: meetingID) == 0)
    }

    @Test
    func updateProgressClampsValuesAndIgnoresRegressions() {
        let meetingID = UUID()
        let center = TranscriptionProgressCenter()
        center.startTracking(meetingID: meetingID)

        center.updateProgress(0.42, for: meetingID)
        center.updateProgress(1.4, for: meetingID)
        center.updateProgress(0.31, for: meetingID)

        #expect(center.progress(for: meetingID) == 1)
    }

    @Test
    func finishTrackingRemovesProgressEntry() {
        let meetingID = UUID()
        let center = TranscriptionProgressCenter()
        center.startTracking(meetingID: meetingID)

        center.finishTracking(meetingID: meetingID)

        #expect(center.progress(for: meetingID) == nil)
    }
}
```

- [ ] **Step 2: Run the targeted test file to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionProgressCenterTests
```

Expected: FAIL because `TranscriptionProgressCenter` does not exist yet.

- [ ] **Step 3: Write the minimal progress center**

```swift
// QuickMeeting/Services/Transcription/TranscriptionProgressCenter.swift
import Foundation

@MainActor
final class TranscriptionProgressCenter: ObservableObject {
    @Published private var progressByMeetingID: [UUID: Double] = [:]

    func startTracking(meetingID: UUID) {
        progressByMeetingID[meetingID] = 0
    }

    func updateProgress(_ progress: Double, for meetingID: UUID) {
        guard let current = progressByMeetingID[meetingID] else {
            return
        }

        let clamped = min(max(progress, 0), 1)
        guard clamped >= current else {
            return
        }

        progressByMeetingID[meetingID] = clamped
    }

    func finishTracking(meetingID: UUID) {
        progressByMeetingID.removeValue(forKey: meetingID)
    }

    func progress(for meetingID: UUID) -> Double? {
        progressByMeetingID[meetingID]
    }
}
```

- [ ] **Step 4: Run the targeted test file again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionProgressCenterTests
```

Expected: PASS for all `TranscriptionProgressCenterTests`.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/TranscriptionProgressCenter.swift QuickMeetingTests/TranscriptionProgressCenterTests.swift
git commit -m "feat: add transcription progress center"
```

## Task 2: Extend The Backend Contract To Report Progress

**Files:**
- Modify: `QuickMeeting/Services/Transcription/WhisperTranscriptionBackend.swift`
- Modify: `QuickMeeting/Services/Transcription/WhisperKitTranscriptionBackend.swift`
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing backend-contract test in the service suite**

```swift
@Test
func transcribeForwardsBackendProgressIntoTheRequest() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createRecordedMeeting()
    await harness.installDefaultModel(.small)
    await harness.backend.setResult(.success(TranscriptionResult(fullText: "Done", segments: [])))

    try await harness.service.transcribe(meetingID: meeting.id)

    let snapshot = await harness.backend.snapshot()
    let request = try #require(snapshot.requests.first)
    #expect(request.onProgress != nil)
}
```

- [ ] **Step 2: Run the service test subset to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: FAIL because `TranscriptionRequest` has no progress callback yet.

- [ ] **Step 3: Add the progress-aware backend contract and adapter**

```swift
// QuickMeeting/Services/Transcription/WhisperTranscriptionBackend.swift
import Foundation

struct TranscriptionRequest: Sendable {
    let audioFileURL: URL
    let model: TranscriptionModel
    let modelFolderURL: URL
    let onProgress: (@Sendable (Double) -> Void)?
}

protocol WhisperTranscriptionBackend: Sendable {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}
```

```swift
// QuickMeeting/Services/Transcription/WhisperKitTranscriptionBackend.swift
func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
    let whisperKit = try await WhisperKit(
        model: request.model.argmaxModelID,
        downloadBase: downloadBaseURL,
        modelFolder: request.modelFolderURL.path,
        download: false
    )

    let progressHandler: @Sendable (Double) -> Void = { progress in
        let clamped = min(max(progress, 0), 1)
        request.onProgress?(clamped)
    }

    let results = try await whisperKit.transcribe(
        audioPath: request.audioFileURL.path,
        decodeOptions: DecodingOptions(language: "RU"),
        progressCallback: progressHandler
    )

    let text = results
        .map(\.text)
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let segments = results
        .flatMap(\.segments)
        .map { segment in
            TranscriptSegment(
                text: segment.text,
                startTime: TimeInterval(segment.start),
                endTime: TimeInterval(segment.end)
            )
        }

    return TranscriptionResult(fullText: text, segments: segments)
}
```

- [ ] **Step 4: Run the service test subset again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS for the new request-shape assertion, with any remaining failures now coming from missing progress orchestration in the service.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/WhisperTranscriptionBackend.swift QuickMeeting/Services/Transcription/WhisperKitTranscriptionBackend.swift QuickMeetingTests/TranscriptionServiceTests.swift
git commit -m "feat: add transcription backend progress reporting"
```

## Task 3: Wire Progress Through TranscriptionService And AppViewModel

**Files:**
- Modify: `QuickMeeting/Services/Transcription/TranscriptionService.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing orchestration tests**

```swift
@Test
func transcribeTracksProgressAndClearsItAfterSuccess() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createRecordedMeeting()
    await harness.installDefaultModel(.small)
    await harness.backend.setResult(.success(TranscriptionResult(fullText: "Done", segments: [])))
    await harness.backend.setProgressUpdates([0.2, 0.6, 1.0])

    try await harness.service.transcribe(meetingID: meeting.id)

    #expect(harness.progressCenter.progress(for: meeting.id) == nil)
    #expect(await harness.backend.snapshot().reportedProgress == [0.2, 0.6, 1.0])
}

@Test
func transcribeClearsProgressAfterFailure() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createRecordedMeeting()
    await harness.installDefaultModel(.small)
    await harness.backend.setProgressUpdates([0.35])
    await harness.backend.setResult(.failure(TestTranscriptionError.failed))

    await #expect(throws: TestTranscriptionError.failed) {
        try await harness.service.transcribe(meetingID: meeting.id)
    }

    #expect(harness.progressCenter.progress(for: meeting.id) == nil)
}
```

```swift
@Test
func transcriptionProgressForMeetingReturnsLiveValue() async throws {
    let harness = try AppViewModelTestHarness()
    let progressCenter = TranscriptionProgressCenter()
    let meetingID = UUID()
    let viewModel = AppViewModel(
        meetingStore: harness.meetingStore,
        meetingFileStore: harness.meetingFileStore,
        recordingService: harness.recordingService,
        transcriptionProgressCenter: progressCenter,
        recordingPermissions: harness.recordingPermissions
    )

    progressCenter.startTracking(meetingID: meetingID)
    progressCenter.updateProgress(0.48, for: meetingID)

    #expect(viewModel.transcriptionProgress(for: meetingID) == 0.48)
}
```

- [ ] **Step 2: Run the targeted test subsets to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: FAIL because the service and view model do not expose progress yet.

- [ ] **Step 3: Add the progress orchestration and app wiring**

```swift
// QuickMeeting/Services/Transcription/TranscriptionService.swift
@MainActor
final class TranscriptionService: TranscriptionServicing {
    private let progressCenter: TranscriptionProgressCenter

    init(
        meetingStore: MeetingStore,
        modelStore: any WhisperModelStore,
        modelSettingsStore: ModelSettingsStore,
        backend: any WhisperTranscriptionBackend,
        progressCenter: TranscriptionProgressCenter,
        artifactWriter: TranscriptionArtifactWriter = .init(),
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.progressCenter = progressCenter
        // keep the existing assignments
    }

    func transcribe(meetingID: UUID) async throws {
        // keep the existing validation logic
        activeMeetingID = meetingID
        try meetingStore.startTranscription(meetingID: meetingID, updatedAt: dateProvider())
        progressCenter.startTracking(meetingID: meetingID)

        defer {
            progressCenter.finishTracking(meetingID: meetingID)
            activeMeetingID = nil
        }

        let request = TranscriptionRequest(
            audioFileURL: audioFileURL,
            model: model,
            modelFolderURL: modelFolderURL,
            onProgress: { [weak progressCenter] progress in
                Task { @MainActor in
                    progressCenter?.updateProgress(progress, for: meetingID)
                }
            }
        )

        do {
            let result = try await backend.transcribe(request)
            let artifacts = try artifactWriter.writeArtifacts(
                for: result,
                in: audioFileURL.deletingLastPathComponent()
            )
            try meetingStore.completeTranscription(
                meetingID: meetingID,
                transcriptFileURL: artifacts.transcriptFileURL,
                transcriptPreview: artifacts.previewText,
                updatedAt: dateProvider()
            )
        } catch {
            try? meetingStore.failTranscription(meetingID: meetingID, updatedAt: dateProvider())
            throw error
        }
    }
}
```

```swift
// QuickMeeting/ViewModels/AppViewModel.swift
@MainActor
final class AppViewModel: ObservableObject {
    let transcriptionProgressCenter: TranscriptionProgressCenter

    init(
        meetingStore: MeetingStore,
        meetingFileStore: MeetingFileStore,
        recordingService: any RecordingService,
        transcriptionService: any TranscriptionServicing = NoopTranscriptionService(),
        transcriptionProgressCenter: TranscriptionProgressCenter = TranscriptionProgressCenter(),
        recordingPermissions: (any RecordingPermissions)? = nil,
        dateProvider: @escaping () -> Date = Date.init,
        meetingIDProvider: @escaping () -> UUID = UUID.init,
        meetingTitleProvider: @escaping (Date) -> String = { _ in "Untitled Meeting" }
    ) {
        self.transcriptionProgressCenter = transcriptionProgressCenter
        // keep the existing assignments
    }

    func transcriptionProgress(for meetingID: UUID) -> Double? {
        transcriptionProgressCenter.progress(for: meetingID)
    }
}
```

```swift
// QuickMeeting/QuickMeetingApp.swift
let transcriptionProgressCenter = TranscriptionProgressCenter()
let transcriptionService = TranscriptionService(
    meetingStore: meetingStore,
    modelStore: modelStore,
    modelSettingsStore: modelSettingsStore,
    backend: WhisperKitTranscriptionBackend(),
    progressCenter: transcriptionProgressCenter
)
_appViewModel = StateObject(
    wrappedValue: AppViewModel(
        meetingStore: meetingStore,
        meetingFileStore: meetingFileStore,
        recordingService: recordingService,
        transcriptionService: transcriptionService,
        transcriptionProgressCenter: transcriptionProgressCenter
    )
)
```

- [ ] **Step 4: Run the targeted test subsets again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS for the new progress orchestration and app-view-model tests.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/TranscriptionService.swift QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/TranscriptionServiceTests.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: track live transcription progress"
```

## Task 4: Add Meeting Detail Progress UI And Support Helpers

**Files:**
- Create: `QuickMeeting/Support/MeetingTranscriptionProgressDisplay.swift`
- Create: `QuickMeetingTests/MeetingTranscriptionProgressDisplayTests.swift`
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeeting/ContentView.swift`

- [ ] **Step 1: Write the failing support-helper tests**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct MeetingTranscriptionProgressDisplayTests {
    @Test
    func progressTextRoundsDownToWholePercent() {
        #expect(transcriptionProgressText(0.428) == "42% complete")
    }

    @Test
    func transcribingMeetingUsesProgressPane() {
        let state = transcriptPaneState(
            meetingStatus: .transcribing,
            transcriptFilePath: nil,
            progress: 0.42
        )

        #expect(state == .transcribing(progress: 0.42))
    }

    @Test
    func completedMeetingKeepsTranscriptPaneEvenWithoutProgress() {
        let state = transcriptPaneState(
            meetingStatus: .completed,
            transcriptFilePath: "/tmp/transcript.txt",
            progress: nil
        )

        #expect(state == .transcriptFile("/tmp/transcript.txt"))
    }
}
```

- [ ] **Step 2: Run the targeted helper tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptionProgressDisplayTests
```

Expected: FAIL because the helper functions and enum do not exist yet.

- [ ] **Step 3: Add the support helper and UI wiring**

```swift
// QuickMeeting/Support/MeetingTranscriptionProgressDisplay.swift
import Foundation

enum TranscriptPaneState: Equatable {
    case empty
    case transcribing(progress: Double)
    case transcriptFile(String)
}

func transcriptPaneState(
    meetingStatus: MeetingStatus,
    transcriptFilePath: String?,
    progress: Double?
) -> TranscriptPaneState {
    if meetingStatus == .transcribing, let progress {
        return .transcribing(progress: min(max(progress, 0), 1))
    }

    if let transcriptFilePath {
        return .transcriptFile(transcriptFilePath)
    }

    return .empty
}

func transcriptionProgressText(_ progress: Double) -> String {
    "\(Int(min(max(progress, 0), 1) * 100))% complete"
}
```

```swift
// QuickMeeting/ContentView.swift
MeetingDetailView(
    meeting: selectedMeeting,
    transcriptionProgress: appViewModel.transcriptionProgress(for: selectedMeeting.id),
    canDelete: appViewModel.canDeleteMeeting(selectedMeeting),
    canTranscribe: appViewModel.canTranscribeMeeting(selectedMeeting),
    onTranscribe: {
        Task {
            await appViewModel.transcribeMeeting(selectedMeeting)
        }
    },
    onDelete: {
        appViewModel.deleteMeeting(selectedMeeting)
    }
)
```

```swift
// QuickMeeting/Views/MeetingDetailView.swift
struct MeetingDetailView: View {
    let meeting: Meeting
    let transcriptionProgress: Double?
    let canDelete: Bool
    let canTranscribe: Bool
    let onTranscribe: () -> Void
    let onDelete: () -> Void

    private var currentTranscriptPaneState: TranscriptPaneState {
        let meetingStatus = (try? meeting.status) ?? .recorded
        return transcriptPaneState(
            meetingStatus: meetingStatus,
            transcriptFilePath: meeting.transcriptFilePath,
            progress: transcriptionProgress
        )
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch currentTranscriptPaneState {
            case .transcriptFile:
                switch transcriptContent {
                case .text(let transcript):
                    ScrollView {
                        Text(transcript)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .lineSpacing(6)
                    }
                case .notAvailable:
                    transcriptEmptyState
                case .unavailable(let message):
                    transcriptUnavailableState(message: message)
                }
            case .transcribing(let progress):
                VStack(spacing: 12) {
                    Text("Transcribing...")
                        .font(.title3)
                        .fontWeight(.semibold)
                    ProgressView(value: progress)
                        .frame(maxWidth: 280)
                    Text(transcriptionProgressText(progress))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                transcriptEmptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }
}
```

- [ ] **Step 4: Run the helper tests and then the full relevant suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptionProgressDisplayTests -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS for the new helper tests and no regressions in the transcription suites.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Support/MeetingTranscriptionProgressDisplay.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/ContentView.swift QuickMeetingTests/MeetingTranscriptionProgressDisplayTests.swift
git commit -m "feat: show transcription progress in meeting detail"
```

## Task 5: Run Final Verification

**Files:**
- Modify: `QuickMeeting/Services/Transcription/WhisperTranscriptionBackend.swift`
- Modify: `QuickMeeting/Services/Transcription/WhisperKitTranscriptionBackend.swift`
- Modify: `QuickMeeting/Services/Transcription/TranscriptionService.swift`
- Modify: `QuickMeeting/Services/Transcription/TranscriptionProgressCenter.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeeting/ContentView.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeeting/Support/MeetingTranscriptionProgressDisplay.swift`
- Modify: `QuickMeetingTests/TranscriptionProgressCenterTests.swift`
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeetingTests/MeetingTranscriptionProgressDisplayTests.swift`

- [ ] **Step 1: Run the full targeted regression suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionProgressCenterTests -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingTranscriptionProgressDisplayTests -only-testing:QuickMeetingTests/MeetingStoreTests
```

Expected: PASS for all transcription-progress and related persistence tests.

- [ ] **Step 2: Run the broader app suite if the targeted tests pass**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
```

Expected: PASS for the full QuickMeeting test suite.

- [ ] **Step 3: Commit the final verification checkpoint**

```bash
git add QuickMeeting QuickMeetingTests
git commit -m "test: verify transcription progress reporting"
```
