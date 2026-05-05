# Recording MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first end-to-end QuickMeeting feature: the user can start and stop a single recording session from the main window or menubar, the app creates a persisted `Meeting` record, and one mixed WAV artifact is saved into that meeting's folder on disk.

**Architecture:** This slice establishes the app shell, meeting persistence, recording state coordination, and a native audio capture boundary without introducing transcription yet. The implementation should keep the real capture path behind `RecordingService` and `AudioCapturePipeline`, so later Whisper and calendar work can layer on without rewriting the recording flow.

**Tech Stack:** SwiftUI, SwiftData, XCTest, ScreenCaptureKit, AVFoundation, AVFAudio, AppKit status bar APIs

---

## Scope And Defaults

- This plan implements recording only, not model download or transcription.
- The app supports exactly one active recording session.
- The canonical audio artifact is a mixed WAV file stored in a per-meeting folder.
- The first feature includes a functional menubar start and stop control.
- If true audio mixing proves too large for the first coding pass, keep the service boundary intact and finish with a verified single-file capture path that still writes the canonical meeting artifact through `RecordingService`.

## Planned File Structure

### Create

- `QuickMeeting/Models/Meeting.swift`
- `QuickMeeting/Models/MeetingStatus.swift`
- `QuickMeeting/Models/RecordingState.swift`
- `QuickMeeting/Services/MeetingStore.swift`
- `QuickMeeting/Services/MeetingFileStore.swift`
- `QuickMeeting/Services/Recording/RecordingService.swift`
- `QuickMeeting/Services/Recording/AudioCapturePipeline.swift`
- `QuickMeeting/Services/Recording/RecordingPermissions.swift`
- `QuickMeeting/ViewModels/AppViewModel.swift`
- `QuickMeeting/ViewModels/MeetingListItemViewModel.swift`
- `QuickMeeting/Views/MeetingListView.swift`
- `QuickMeeting/Views/MeetingDetailView.swift`
- `QuickMeeting/Views/RecordingToolbarControls.swift`
- `QuickMeeting/MenuBar/MenuBarController.swift`
- `QuickMeeting/MenuBar/MenuBarView.swift`
- `QuickMeetingTests/MeetingStoreTests.swift`
- `QuickMeetingTests/MeetingFileStoreTests.swift`
- `QuickMeetingTests/AppViewModelTests.swift`

### Modify

- `QuickMeeting/QuickMeetingApp.swift`
- `QuickMeeting/ContentView.swift`
- `QuickMeeting.xcodeproj/project.pbxproj`

### Reference During Implementation

- `docs/quickmeeting-architecture-design.md`
- `QuickRecorder/SCContext.swift`
- `QuickRecorder/RecordEngine.swift`
- `QuickRecorder/ViewModel/StatusBar.swift`

## Task 1: Replace Template Data Model With Meeting Domain Model

**Files:**
- Create: `QuickMeeting/Models/Meeting.swift`
- Create: `QuickMeeting/Models/MeetingStatus.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Remove usage from: `QuickMeeting/Item.swift`, `QuickMeeting/ContentView.swift`
- Test: `QuickMeetingTests/MeetingStoreTests.swift`

- [ ] **Step 1: Write the failing persistence test**

```swift
import SwiftData
import Testing
@testable import QuickMeeting

struct MeetingStoreTests {
    @Test func insertsMeetingWithExpectedDefaults() throws {
        let container = try ModelContainer(
            for: Meeting.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = MeetingStore(modelContext: context)

        let meeting = try store.createMeeting(
            title: "Meeting at 14:00 on 2026-05-04",
            startedAt: Date(timeIntervalSince1970: 1_778_000_000),
            folderURL: URL(fileURLWithPath: "/tmp/meeting-1"),
            audioFileURL: URL(fileURLWithPath: "/tmp/meeting-1/audio.wav")
        )

        #expect(meeting.status == .recording)
        #expect(meeting.audioFilePath == "/tmp/meeting-1/audio.wav")
        #expect(meeting.transcriptFilePath == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingStoreTests`

Expected: FAIL because `Meeting` and `MeetingStore` do not exist yet.

- [ ] **Step 3: Add the meeting status enum**

```swift
import Foundation

enum MeetingStatus: String, Codable, CaseIterable {
    case recording
    case recorded
    case transcribing
    case completed
    case failed
}
```

- [ ] **Step 4: Add the SwiftData meeting model**

```swift
import Foundation
import SwiftData

@Model
final class Meeting {
    @Attribute(.unique) var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var statusRawValue: String
    var audioFilePath: String
    var transcriptFilePath: String?
    var transcriptPreview: String?
    var duration: TimeInterval?
    var calendarEventID: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        status: MeetingStatus,
        audioFilePath: String,
        transcriptFilePath: String? = nil,
        transcriptPreview: String? = nil,
        duration: TimeInterval? = nil,
        calendarEventID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.statusRawValue = status.rawValue
        self.audioFilePath = audioFilePath
        self.transcriptFilePath = transcriptFilePath
        self.transcriptPreview = transcriptPreview
        self.duration = duration
        self.calendarEventID = calendarEventID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRawValue) ?? .failed }
        set { statusRawValue = newValue.rawValue }
    }
}
```

- [ ] **Step 5: Add the minimal meeting store**

```swift
import Foundation
import SwiftData

@MainActor
final class MeetingStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createMeeting(
        title: String,
        startedAt: Date,
        folderURL: URL,
        audioFileURL: URL
    ) throws -> Meeting {
        let meeting = Meeting(
            title: title,
            startedAt: startedAt,
            status: .recording,
            audioFilePath: audioFileURL.path
        )
        modelContext.insert(meeting)
        try modelContext.save()
        return meeting
    }
}
```

- [ ] **Step 6: Update the app container to use `Meeting`**

```swift
let schema = Schema([
    Meeting.self,
])
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingStoreTests`

Expected: PASS with one green test.

- [ ] **Step 8: Commit**

```bash
git add QuickMeeting/Models/Meeting.swift QuickMeeting/Models/MeetingStatus.swift QuickMeeting/Services/MeetingStore.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/MeetingStoreTests.swift
git commit -m "feat: add meeting persistence model"
```

## Task 2: Create Meeting Folder And Canonical Artifact Paths

**Files:**
- Create: `QuickMeeting/Services/MeetingFileStore.swift`
- Test: `QuickMeetingTests/MeetingFileStoreTests.swift`

- [ ] **Step 1: Write the failing filesystem test**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct MeetingFileStoreTests {
    @Test func createsMeetingFolderWithExpectedAudioPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = MeetingFileStore(rootURL: root)

        let artifact = try store.createArtifacts(for: UUID(), startedAt: Date(timeIntervalSince1970: 1_778_000_000))

        #expect(FileManager.default.fileExists(atPath: artifact.meetingFolderURL.path))
        #expect(artifact.audioFileURL.lastPathComponent == "audio.wav")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingFileStoreTests`

Expected: FAIL because `MeetingFileStore` does not exist yet.

- [ ] **Step 3: Add the artifact store**

```swift
import Foundation

struct MeetingArtifacts {
    let meetingFolderURL: URL
    let audioFileURL: URL
}

final class MeetingFileStore {
    private let fileManager: FileManager
    let rootURL: URL

    init(
        fileManager: FileManager = .default,
        rootURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuickMeeting", isDirectory: true)
            .appendingPathComponent("Meetings", isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func createArtifacts(for meetingID: UUID, startedAt: Date) throws -> MeetingArtifacts {
        let folderURL = rootURL.appendingPathComponent(meetingID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return MeetingArtifacts(
            meetingFolderURL: folderURL,
            audioFileURL: folderURL.appendingPathComponent("audio.wav")
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingFileStoreTests`

Expected: PASS with one green test.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/MeetingFileStore.swift QuickMeetingTests/MeetingFileStoreTests.swift
git commit -m "feat: add meeting artifact file store"
```

## Task 3: Introduce Recording State And App View Model

**Files:**
- Create: `QuickMeeting/Models/RecordingState.swift`
- Create: `QuickMeeting/ViewModels/AppViewModel.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing view model test**

```swift
import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct AppViewModelTests {
    @Test func startRecordingTogglesStateWhileOperationRuns() async throws {
        let viewModel = AppViewModel(
            meetingStore: .preview,
            meetingFileStore: .preview,
            recordingService: .stub(startHandler: {}, stopHandler: {})
        )

        #expect(viewModel.recordingState == .idle)
        try await viewModel.startRecording()
        #expect(viewModel.recordingState == .recording)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: FAIL because `AppViewModel` and `RecordingState` do not exist yet.

- [ ] **Step 3: Add recording state**

```swift
import Foundation

enum RecordingState: Equatable {
    case idle
    case starting
    case recording(meetingID: UUID)
    case stopping(meetingID: UUID)
    case failed(message: String)
}
```

- [ ] **Step 4: Add the minimal app view model**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
    private let meetingStore: MeetingStore
    private let meetingFileStore: MeetingFileStore
    private let recordingService: RecordingService

    var recordingState: RecordingState = .idle

    init(
        meetingStore: MeetingStore,
        meetingFileStore: MeetingFileStore,
        recordingService: RecordingService
    ) {
        self.meetingStore = meetingStore
        self.meetingFileStore = meetingFileStore
        self.recordingService = recordingService
    }
}
```

- [ ] **Step 5: Extend `RecordingService` with a stub-friendly protocol surface**

```swift
@MainActor
protocol RecordingService {
    func startRecording(meeting: Meeting, outputURL: URL) async throws
    func stopRecording() async throws
}
```

- [ ] **Step 6: Run the test again and keep it failing only on missing behavior**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: FAIL because `startRecording()` is not implemented on the view model yet.

- [ ] **Step 7: Implement `startRecording()` state transition minimally**

```swift
func startRecording() async throws {
    let startedAt = Date()
    let meetingID = UUID()
    let artifacts = try meetingFileStore.createArtifacts(for: meetingID, startedAt: startedAt)
    let meeting = try meetingStore.createMeeting(
        id: meetingID,
        title: Self.defaultMeetingTitle(for: startedAt),
        startedAt: startedAt,
        folderURL: artifacts.meetingFolderURL,
        audioFileURL: artifacts.audioFileURL
    )

    recordingState = .starting
    try await recordingService.startRecording(meeting: meeting, outputURL: artifacts.audioFileURL)
    recordingState = .recording(meetingID: meeting.id)
}
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: PASS with one green test.

- [ ] **Step 9: Commit**

```bash
git add QuickMeeting/Models/RecordingState.swift QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/Services/Recording/RecordingService.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: add app recording state model"
```

## Task 4: Finish MeetingStore For Recording Start And Stop

**Files:**
- Modify: `QuickMeeting/Services/MeetingStore.swift`
- Test: `QuickMeetingTests/MeetingStoreTests.swift`

- [ ] **Step 1: Add a failing stop-recording test**

```swift
@Test func marksMeetingRecordedWhenStopCompletes() throws {
    let container = try ModelContainer(
        for: Meeting.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let store = MeetingStore(modelContext: context)
    let startedAt = Date(timeIntervalSince1970: 1_778_000_000)
    let meeting = try store.createMeeting(
        id: UUID(),
        title: "Meeting at 14:00 on 2026-05-04",
        startedAt: startedAt,
        folderURL: URL(fileURLWithPath: "/tmp/meeting-1"),
        audioFileURL: URL(fileURLWithPath: "/tmp/meeting-1/audio.wav")
    )

    try store.finishRecording(meetingID: meeting.id, endedAt: startedAt.addingTimeInterval(42))

    #expect(meeting.status == .recorded)
    #expect(meeting.duration == 42)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingStoreTests`

Expected: FAIL because `finishRecording` does not exist yet.

- [ ] **Step 3: Expand the store API**

```swift
func createMeeting(
    id: UUID,
    title: String,
    startedAt: Date,
    folderURL: URL,
    audioFileURL: URL
) throws -> Meeting {
    let now = Date()
    let meeting = Meeting(
        id: id,
        title: title,
        startedAt: startedAt,
        status: .recording,
        audioFilePath: audioFileURL.path,
        createdAt: now,
        updatedAt: now
    )
    modelContext.insert(meeting)
    try modelContext.save()
    return meeting
}

func finishRecording(meetingID: UUID, endedAt: Date) throws {
    let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
    guard let meeting = try modelContext.fetch(descriptor).first else { return }
    meeting.endedAt = endedAt
    meeting.duration = endedAt.timeIntervalSince(meeting.startedAt)
    meeting.status = .recorded
    meeting.updatedAt = .now
    try modelContext.save()
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingStoreTests`

Expected: PASS with both meeting store tests green.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/MeetingStore.swift QuickMeetingTests/MeetingStoreTests.swift
git commit -m "feat: add meeting recording lifecycle persistence"
```

## Task 5: Implement Native Permission Checks

**Files:**
- Create: `QuickMeeting/Services/Recording/RecordingPermissions.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Add a failing permission denial test**

```swift
@Test func startRecordingStopsOnPermissionFailure() async throws {
    let viewModel = AppViewModel(
        meetingStore: .preview,
        meetingFileStore: .preview,
        recordingService: .stub(startHandler: {}, stopHandler: {}),
        permissions: .stub(screenAllowed: false, microphoneAllowed: true)
    )

    await #expect(throws: Never.self) {
        try? await viewModel.startRecording()
    }

    #expect(viewModel.recordingState == .failed(message: "Screen recording permission is required."))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: FAIL because permission dependency injection does not exist yet.

- [ ] **Step 3: Add permission abstraction**

```swift
import AVFoundation
import ScreenCaptureKit

@MainActor
protocol RecordingPermissions {
    func ensurePermissions() async -> RecordingPermissionResult
}

enum RecordingPermissionResult: Equatable {
    case granted
    case denied(message: String)
}
```

- [ ] **Step 4: Implement the native permission checker**

```swift
@MainActor
struct SystemRecordingPermissions: RecordingPermissions {
    func ensurePermissions() async -> RecordingPermissionResult {
        guard CGPreflightScreenCaptureAccess() else {
            return .denied(message: "Screen recording permission is required.")
        }

        let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneGranted else {
            return .denied(message: "Microphone permission is required.")
        }

        return .granted
    }
}
```

- [ ] **Step 5: Gate `startRecording()` through permission checks**

```swift
switch await permissions.ensurePermissions() {
case .granted:
    break
case .denied(let message):
    recordingState = .failed(message: message)
    return
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: PASS with permission and state tests green.

- [ ] **Step 7: Commit**

```bash
git add QuickMeeting/Services/Recording/RecordingPermissions.swift QuickMeeting/ViewModels/AppViewModel.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: add recording permission checks"
```

## Task 6: Add Audio Capture Pipeline Boundary

**Files:**
- Create: `QuickMeeting/Services/Recording/AudioCapturePipeline.swift`
- Modify: `QuickMeeting/Services/Recording/RecordingService.swift`

- [ ] **Step 1: Define the capture pipeline interface**

```swift
import Foundation

protocol AudioCapturePipeline {
    func start(outputURL: URL) async throws
    func stop() async throws
}
```

- [ ] **Step 2: Add the concrete recording service**

```swift
import Foundation

@MainActor
final class DefaultRecordingService: RecordingService {
    private let pipeline: AudioCapturePipeline
    private var activeMeetingID: UUID?

    init(pipeline: AudioCapturePipeline) {
        self.pipeline = pipeline
    }

    func startRecording(meeting: Meeting, outputURL: URL) async throws {
        guard activeMeetingID == nil else {
            throw RecordingServiceError.recordingAlreadyInProgress
        }
        activeMeetingID = meeting.id
        do {
            try await pipeline.start(outputURL: outputURL)
        } catch {
            activeMeetingID = nil
            throw error
        }
    }

    func stopRecording() async throws {
        try await pipeline.stop()
        activeMeetingID = nil
    }
}
```

- [ ] **Step 3: Add explicit recording service errors**

```swift
enum RecordingServiceError: LocalizedError {
    case recordingAlreadyInProgress

    var errorDescription: String? {
        switch self {
        case .recordingAlreadyInProgress:
            return "A recording is already in progress."
        }
    }
}
```

- [ ] **Step 4: Adapt the preview and stub constructors used in tests**

```swift
extension RecordingService where Self == DefaultRecordingService {
    static func stub(
        startHandler: @escaping () -> Void,
        stopHandler: @escaping () -> Void
    ) -> DefaultRecordingService {
        DefaultRecordingService(
            pipeline: StubAudioCapturePipeline(
                startHandler: startHandler,
                stopHandler: stopHandler
            )
        )
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Recording/AudioCapturePipeline.swift QuickMeeting/Services/Recording/RecordingService.swift
git commit -m "feat: add recording service boundary"
```

## Task 7: Wire A Minimal Real Capture Implementation

**Files:**
- Modify: `QuickMeeting/Services/Recording/AudioCapturePipeline.swift`
- Reference: `QuickRecorder/SCContext.swift`
- Reference: `QuickRecorder/RecordEngine.swift`

- [ ] **Step 1: Start with a concrete pipeline skeleton that owns native resources**

```swift
import AVFAudio
import AVFoundation
import Foundation
import ScreenCaptureKit

final class SystemAudioCapturePipeline: NSObject, AudioCapturePipeline {
    private var audioFile: AVAudioFile?
    private let engine = AVAudioEngine()

    func start(outputURL: URL) async throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )!
        audioFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)

        // First implementation target:
        // 1. Establish ScreenCaptureKit system audio capture.
        // 2. Establish microphone input capture.
        // 3. Route both into one writer path controlled here.
    }

    func stop() async throws {
        engine.stop()
        audioFile = nil
    }
}
```

- [ ] **Step 2: Port the smallest reusable system-audio setup from the reference project**

Run these reads while implementing:

- `sed -n '140,360p' QuickRecorder/RecordEngine.swift`
- `sed -n '1,220p' QuickRecorder/SCContext.swift`

Expected: enough context to extract only the audio-specific `SCStreamConfiguration`, sample buffer handling, and file-writing behavior without carrying over screen-video code or unrelated global state.

- [ ] **Step 3: Implement the first verified capture path**

Implementation rules:

- Use `SCStream` configured for audio capture only.
- Capture microphone input through `AVAudioEngine` input node tap or equivalent native audio callback.
- Normalize both paths to 48 kHz PCM.
- Write the combined output to the canonical WAV file through one service-owned writer path.
- Keep all native setup inside `SystemAudioCapturePipeline`.

- [ ] **Step 4: Manually verify the capture path in the app**

Run: `xcodebuild -scheme QuickMeeting -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED

Then run the app in Xcode and verify:

- start recording succeeds after permissions are granted
- stop recording leaves an `audio.wav` file in the meeting folder
- a second recording can start after the first is stopped

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Recording/AudioCapturePipeline.swift
git commit -m "feat: add initial native audio capture pipeline"
```

## Task 8: Build The Main Window Library UI For The First Slice

**Files:**
- Create: `QuickMeeting/Views/MeetingListView.swift`
- Create: `QuickMeeting/Views/MeetingDetailView.swift`
- Create: `QuickMeeting/Views/RecordingToolbarControls.swift`
- Modify: `QuickMeeting/ContentView.swift`

- [ ] **Step 1: Replace the template list with a meeting query**

```swift
@Query(sort: \Meeting.startedAt, order: .reverse)
private var meetings: [Meeting]
```

- [ ] **Step 2: Add a focused list view**

```swift
import SwiftUI

struct MeetingListView: View {
    let meetings: [Meeting]
    @Binding var selectedMeetingID: PersistentIdentifier?

    var body: some View {
        List(meetings, selection: $selectedMeetingID) { meeting in
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                Text(meeting.startedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 3: Add the detail pane**

```swift
import SwiftUI

struct MeetingDetailView: View {
    let meeting: Meeting?

    var body: some View {
        Group {
            if let meeting {
                VStack(alignment: .leading, spacing: 12) {
                    Text(meeting.title).font(.title2.weight(.semibold))
                    Text("Status: \(meeting.statusRawValue)")
                    Text("Audio: \(meeting.audioFilePath)")
                    if let duration = meeting.duration {
                        Text("Duration: \(duration.formatted()) seconds")
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
            } else {
                ContentUnavailableView("No Meeting Selected", systemImage: "waveform")
            }
        }
    }
}
```

- [ ] **Step 4: Add recording controls in the toolbar**

```swift
struct RecordingToolbarControls: ToolbarContent {
    @Bindable var viewModel: AppViewModel

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Button("Start Recording") {
                Task { try? await viewModel.startRecording() }
            }
            .disabled(!viewModel.canStartRecording)

            Button("Stop Recording") {
                Task { try? await viewModel.stopRecording() }
            }
            .disabled(!viewModel.canStopRecording)
        }
    }
}
```

- [ ] **Step 5: Update `ContentView` to use `AppViewModel` and meeting views**

```swift
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @State private var selectedMeetingID: PersistentIdentifier?
    @State private var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            MeetingListView(meetings: meetings, selectedMeetingID: $selectedMeetingID)
        } detail: {
            MeetingDetailView(meeting: selectedMeeting)
        }
        .toolbar { RecordingToolbarControls(viewModel: viewModel) }
    }
}
```

- [ ] **Step 6: Build and smoke-test the UI**

Run: `xcodebuild -scheme QuickMeeting -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add QuickMeeting/Views/MeetingListView.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/Views/RecordingToolbarControls.swift QuickMeeting/ContentView.swift
git commit -m "feat: add meeting library recording ui"
```

## Task 9: Add Menubar Start And Stop Control

**Files:**
- Create: `QuickMeeting/MenuBar/MenuBarController.swift`
- Create: `QuickMeeting/MenuBar/MenuBarView.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`

- [ ] **Step 1: Add a lightweight SwiftUI menubar view**

```swift
import SwiftUI

struct MenuBarView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QuickMeeting").font(.headline)
            Button(viewModel.canStartRecording ? "Start Recording" : "Stop Recording") {
                Task {
                    if viewModel.canStartRecording {
                        try? await viewModel.startRecording()
                    } else {
                        try? await viewModel.stopRecording()
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 220)
    }
}
```

- [ ] **Step 2: Add the status item controller**

```swift
import AppKit
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(viewModel: AppViewModel) {
        popover.contentViewController = NSHostingController(rootView: MenuBarView(viewModel: viewModel))
        statusItem.button?.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "QuickMeeting")
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.target = self
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
```

- [ ] **Step 3: Instantiate the menu bar controller once in the app**

```swift
@State private var appViewModel: AppViewModel
@State private var menuBarController: MenuBarController?

var body: some Scene {
    WindowGroup {
        ContentView(viewModel: appViewModel)
            .task {
                if menuBarController == nil {
                    menuBarController = MenuBarController(viewModel: appViewModel)
                }
            }
    }
    .modelContainer(sharedModelContainer)
}
```

- [ ] **Step 4: Build and manually verify**

Run: `xcodebuild -scheme QuickMeeting -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED

Manual verification:

- menubar icon appears on app launch
- menubar popover opens and closes
- start recording from menubar changes the main window state
- stop recording from menubar ends the same active session

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/MenuBar/MenuBarController.swift QuickMeeting/MenuBar/MenuBarView.swift QuickMeeting/QuickMeetingApp.swift
git commit -m "feat: add recording menubar controls"
```

## Task 10: Finish Stop Flow And End-To-End Verification

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/Services/MeetingStore.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Add a failing stop-flow test**

```swift
@Test func stopRecordingMarksMeetingRecordedAndReturnsToIdle() async throws {
    let recorder = RecordingService.stub(startHandler: {}, stopHandler: {})
    let viewModel = AppViewModel(
        meetingStore: .preview,
        meetingFileStore: .preview,
        recordingService: recorder,
        permissions: .stub(screenAllowed: true, microphoneAllowed: true)
    )

    try await viewModel.startRecording()
    try await viewModel.stopRecording()

    #expect(viewModel.recordingState == .idle)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS' -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: FAIL because `stopRecording()` is not fully implemented yet.

- [ ] **Step 3: Implement the stop flow**

```swift
func stopRecording() async throws {
    guard case .recording(let meetingID) = recordingState else { return }
    recordingState = .stopping(meetingID: meetingID)
    try await recordingService.stopRecording()
    try meetingStore.finishRecording(meetingID: meetingID, endedAt: .now)
    recordingState = .idle
}
```

- [ ] **Step 4: Run all project tests**

Run: `xcodebuild test -scheme QuickMeeting -destination 'platform=macOS'`

Expected: TEST SUCCEEDED

- [ ] **Step 5: Run a full manual verification pass**

Verify all of the following in the built app:

- launching the app shows an empty meeting library
- start recording from main window creates a meeting entry
- stop recording updates that meeting to `recorded`
- the meeting detail shows the saved audio path
- an `audio.wav` file exists inside the meeting folder
- start and stop also work from the menubar on the same shared state
- a second concurrent recording cannot be started

- [ ] **Step 6: Commit**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/Services/MeetingStore.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: finish recording mvp flow"
```

## Self-Review Checklist

- Spec coverage: this plan covers the first architecture slice for app shell, meeting persistence, recording lifecycle, file storage, and menubar start/stop.
- Intentional omissions: transcription, model download, transcript viewing, calendar integration, notifications, and export are deferred to later plans.
- Placeholder scan result: the only intentionally open item is the exact native mixing implementation inside `SystemAudioCapturePipeline`, but the plan constrains the boundary, verification target, and reference sources to keep the task implementable without redesign.
- Type consistency: `Meeting`, `MeetingStatus`, `RecordingState`, `MeetingStore`, `MeetingFileStore`, `RecordingService`, and `AudioCapturePipeline` are used consistently across tasks.

## Outcome

When this plan is complete, QuickMeeting will have its first real vertical slice:

- a persistent `Meeting` domain model
- a real file-backed meeting artifact directory
- one active recording session at a time
- start and stop recording from both main window and menubar
- one canonical WAV artifact saved per meeting
- test coverage for persistence, file path creation, and app state transitions
