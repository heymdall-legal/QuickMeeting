**Goal:** Move transcript persistence fully into SwiftData so each meeting stores all metadata and transcript structure in the database, with only `audio.wav` remaining on disk.

**Architecture:** `Meeting` stays the aggregate root and gains meeting-owned transcript speaker and segment data while losing `transcriptFilePath`. `MeetingStore` becomes the canonical persistence boundary for transcript writes and speaker rename updates, and transcript display is rendered in memory from stored structured data instead of file reads.

**Tech Stack:** Swift, SwiftData, SwiftUI, Testing

---

## File Structure

**Create:**
- `QuickMeeting/Models/PersistedTranscriptSpeaker.swift`
- `QuickMeeting/Models/PersistedTranscriptSegment.swift`

**Modify:**
- `QuickMeeting/Models/Meeting.swift`
- `QuickMeeting/Services/MeetingStore.swift`
- `QuickMeeting/Services/Transcription/TranscriptionService.swift`
- `QuickMeeting/Services/Transcription/MeetingTranscriptStore.swift`
- `QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift`
- `QuickMeeting/Support/MeetingTranscriptContent.swift`
- `QuickMeeting/Views/MeetingDetailView.swift`
- `QuickMeeting/ViewModels/AppViewModel.swift`
- `QuickMeeting/QuickMeetingApp.swift`
- `QuickMeetingTests/MeetingStoreTests.swift`
- `QuickMeetingTests/MeetingTranscriptStoreTests.swift`
- `QuickMeetingTests/MeetingTranscriptContentTests.swift`
- `QuickMeetingTests/TranscriptionServiceTests.swift`
- `QuickMeetingTests/AppViewModelTests.swift`
- `docs/quickmeeting-architecture-design.md`

**Why these files:**
- `Meeting.swift` is the aggregate boundary and needs the schema change.
- `MeetingStore.swift` already owns lifecycle updates and should absorb transcript persistence.
- `TranscriptionService.swift` currently writes files and must switch to database writes.
- `MeetingTranscriptStore.swift`, `MeetingTranscriptContent.swift`, `MeetingDetailView.swift`, and `AppViewModel.swift` form the transcript read/edit path and must stop depending on transcript files.
- Tests need to move from “file exists” assertions to “transcript structure persisted and renderable” assertions.

### Task 1: Add SwiftData-backed transcript models to `Meeting`

**Files:**
- Create: `QuickMeeting/Models/PersistedTranscriptSpeaker.swift`
- Create: `QuickMeeting/Models/PersistedTranscriptSegment.swift`
- Modify: `QuickMeeting/Models/Meeting.swift`
- Test: `QuickMeetingTests/MeetingStoreTests.swift`

- [ ] **Step 1: Write the failing schema persistence test**

```swift
@Test
func completeTranscriptionPersistsStructuredTranscriptData() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.createRecordedMeeting()
    let updatedAt = Date(timeIntervalSince1970: 1_234_568_100)
    let transcript = StoredTranscript(
        speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
        segments: [TranscriptSegment(text: "First line", startTime: 0, endTime: 1, speakerID: "speaker-1")]
    )

    try harness.store.completeTranscription(
        meetingID: meeting.id,
        transcript: transcript,
        transcriptPreview: "First line",
        updatedAt: updatedAt
    )

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .completed)
    #expect(reloaded.transcriptPreview == "First line")
    #expect(reloaded.transcriptSpeakers.map(\.displayName) == ["Speaker 1"])
    #expect(reloaded.transcriptSegments.map(\.text) == ["First line"])
}
```

- [ ] **Step 2: Run the targeted store test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests`

Expected: FAIL with missing `completeTranscription(meetingID:transcript:transcriptPreview:updatedAt:)` or missing `transcriptSpeakers` / `transcriptSegments` members on `Meeting`.

- [ ] **Step 3: Add persisted transcript speaker and segment models**

```swift
import Foundation
import SwiftData

@Model
final class PersistedTranscriptSpeaker {
    var id: String
    var displayName: String

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    convenience init(_ speaker: TranscriptSpeaker) {
        self.init(id: speaker.id, displayName: speaker.displayName)
    }

    var value: TranscriptSpeaker {
        TranscriptSpeaker(id: id, displayName: displayName)
    }
}
```

```swift
import Foundation
import SwiftData

@Model
final class PersistedTranscriptSegment {
    var id: UUID
    var text: String
    var startTime: TimeInterval?
    var endTime: TimeInterval?
    var speakerID: String?

    init(
        id: UUID,
        text: String,
        startTime: TimeInterval?,
        endTime: TimeInterval?,
        speakerID: String?
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speakerID = speakerID
    }

    convenience init(_ segment: TranscriptSegment) {
        self.init(
            id: segment.id,
            text: segment.text,
            startTime: segment.startTime,
            endTime: segment.endTime,
            speakerID: segment.speakerID
        )
    }

    var value: TranscriptSegment {
        TranscriptSegment(
            id: id,
            text: text,
            startTime: startTime,
            endTime: endTime,
            speakerID: speakerID
        )
    }
}
```

- [ ] **Step 4: Update `Meeting` to own transcript structure**

```swift
@Model
final class Meeting {
    @Attribute(.unique) private(set) var id: UUID
    private(set) var title: String
    private(set) var startedAt: Date
    private(set) var endedAt: Date?
    private var statusRawValue: String
    private(set) var audioFilePath: String
    private(set) var transcriptPreview: String?
    @Relationship(deleteRule: .cascade) private(set) var transcriptSpeakers: [PersistedTranscriptSpeaker]
    @Relationship(deleteRule: .cascade) private(set) var transcriptSegments: [PersistedTranscriptSegment]
    private(set) var duration: TimeInterval?
    private(set) var calendarEventID: String?
    private(set) var createdAt: Date
    private(set) var updatedAt: Date

    var storedTranscript: StoredTranscript? {
        guard !transcriptSpeakers.isEmpty || !transcriptSegments.isEmpty else {
            return nil
        }

        return StoredTranscript(
            speakers: transcriptSpeakers.map(\.value),
            segments: transcriptSegments.map(\.value)
        )
    }

    func beginTranscription(updatedAt: Date = Date()) {
        transcriptPreview = nil
        transcriptSpeakers.removeAll()
        transcriptSegments.removeAll()
        statusRawValue = MeetingStatus.transcribing.rawValue
        touch(updatedAt: updatedAt)
    }

    func completeTranscription(
        transcript: StoredTranscript,
        transcriptPreview: String,
        updatedAt: Date = Date()
    ) {
        self.transcriptPreview = transcriptPreview
        transcriptSpeakers = transcript.speakers.map(PersistedTranscriptSpeaker.init)
        transcriptSegments = transcript.segments.map(PersistedTranscriptSegment.init)
        statusRawValue = MeetingStatus.completed.rawValue
        touch(updatedAt: updatedAt)
    }
}
```

- [ ] **Step 5: Update the in-memory test container schema**

```swift
let schema = Schema([
    Meeting.self,
    PersistedTranscriptSpeaker.self,
    PersistedTranscriptSegment.self,
])
```

- [ ] **Step 6: Re-run the targeted store test and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests`

Expected: PASS for the new structured transcript persistence test.

- [ ] **Step 7: Commit the schema change**

```bash
git add QuickMeeting/Models/PersistedTranscriptSpeaker.swift QuickMeeting/Models/PersistedTranscriptSegment.swift QuickMeeting/Models/Meeting.swift QuickMeetingTests/MeetingStoreTests.swift
git commit -m "feat: store meeting transcripts in swiftdata"
```

### Task 2: Move transcript persistence and rename logic into `MeetingStore`

**Files:**
- Modify: `QuickMeeting/Services/MeetingStore.swift`
- Modify: `QuickMeeting/Services/Transcription/MeetingTranscriptStore.swift`
- Modify: `QuickMeetingTests/MeetingStoreTests.swift`
- Modify: `QuickMeetingTests/MeetingTranscriptStoreTests.swift`

- [ ] **Step 1: Write the failing rename-speaker test against the DB-backed store**

```swift
@Test
func renameSpeakerUpdatesPersistedMeetingTranscript() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.createRecordedMeeting()
    try harness.store.completeTranscription(
        meetingID: meeting.id,
        transcript: StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
        ),
        transcriptPreview: "Hello",
        updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
    )

    try harness.store.renameSpeaker(
        meetingID: meeting.id,
        speakerID: "speaker-1",
        displayName: "Masha",
        updatedAt: Date(timeIntervalSince1970: 1_234_568_200)
    )

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(reloaded.transcriptSpeakers.map(\.displayName) == ["Masha"])
    #expect(reloaded.transcriptSegments.map(\.speakerID) == ["speaker-1"])
}
```

- [ ] **Step 2: Run the transcript-store test target and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests`

Expected: FAIL because `MeetingStore` has no rename API and `MeetingTranscriptStore` still expects a folder URL.

- [ ] **Step 3: Add transcript write and rename APIs to `MeetingStore`**

```swift
func completeTranscription(
    meetingID: UUID,
    transcript: StoredTranscript,
    transcriptPreview: String,
    updatedAt: Date
) throws {
    let meeting = try fetchMeeting(id: meetingID)
    meeting.completeTranscription(
        transcript: transcript,
        transcriptPreview: transcriptPreview,
        updatedAt: updatedAt
    )
    try modelContext.save()
}

@discardableResult
func renameSpeaker(
    meetingID: UUID,
    speakerID: String,
    displayName: String,
    updatedAt: Date
) throws -> StoredTranscript {
    let meeting = try fetchMeeting(id: meetingID)
    guard let speaker = meeting.transcriptSpeakers.first(where: { $0.id == speakerID }) else {
        throw MeetingTranscriptStoreError.speakerNotFound
    }

    speaker.displayName = displayName
    meeting.setStatus(try meeting.status, updatedAt: updatedAt)
    try modelContext.save()
    return try #require(meeting.storedTranscript)
}
```

- [ ] **Step 4: Convert `MeetingTranscriptStore` into a DB-backed wrapper**

```swift
protocol MeetingTranscriptStoring: Sendable {
    func loadTranscript(meetingID: UUID) throws -> StoredTranscript
    func renameSpeaker(id: String, to displayName: String, in meetingID: UUID) throws -> StoredTranscript
}

struct MeetingTranscriptStore: MeetingTranscriptStoring {
    let meetingStore: MeetingStore
    let dateProvider: () -> Date

    func loadTranscript(meetingID: UUID) throws -> StoredTranscript {
        let meeting = try meetingStore.fetchMeeting(id: meetingID)
        guard let transcript = meeting.storedTranscript else {
            throw MeetingTranscriptStoreError.sidecarMissing
        }
        return transcript
    }

    func renameSpeaker(id: String, to displayName: String, in meetingID: UUID) throws -> StoredTranscript {
        try meetingStore.renameSpeaker(
            meetingID: meetingID,
            speakerID: id,
            displayName: displayName,
            updatedAt: dateProvider()
        )
    }
}
```

- [ ] **Step 5: Rename the legacy error case to match DB semantics**

```swift
enum MeetingTranscriptStoreError: LocalizedError, Equatable {
    case transcriptMissing
    case speakerNotFound

    var errorDescription: String? {
        switch self {
        case .transcriptMissing:
            "Transcript data is unavailable."
        case .speakerNotFound:
            "Speaker could not be updated."
        }
    }
}
```

- [ ] **Step 6: Update the tests to use meeting IDs instead of folder URLs**

```swift
let updated = try store.renameSpeaker(id: "speaker-1", to: "Masha", in: meeting.id)
#expect(updated.speakers.first?.displayName == "Masha")
```

- [ ] **Step 7: Re-run the transcript store tests and verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests`

Expected: PASS for store-backed transcript persistence and rename tests.

- [ ] **Step 8: Commit the store boundary change**

```bash
git add QuickMeeting/Services/MeetingStore.swift QuickMeeting/Services/Transcription/MeetingTranscriptStore.swift QuickMeetingTests/MeetingStoreTests.swift QuickMeetingTests/MeetingTranscriptStoreTests.swift
git commit -m "refactor: move transcript persistence into meeting store"
```

### Task 3: Change transcription from file artifacts to DB writes

**Files:**
- Modify: `QuickMeeting/Services/Transcription/TranscriptionService.swift`
- Modify: `QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift`
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing transcription-service test for DB persistence**

```swift
@Test
func transcribeRecordedMeetingPersistsStructuredTranscriptAndCompletesMeeting() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createRecordedMeeting()
    await harness.installDefaultModel(.small)
    await harness.backend.setResult(.success(
        TranscriptionResult(
            fullText: "Transcript body",
            segments: [TranscriptSegment(text: "Transcript body", startTime: 0, endTime: 1)]
        )
    ))
    await harness.diarizer.setResult(.success(
        StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Transcript body", startTime: 0, endTime: 1, speakerID: "speaker-1")]
        )
    ))

    try await harness.service.transcribe(meetingID: meeting.id)

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .completed)
    #expect(reloaded.transcriptPreview == "Transcript body")
    #expect(reloaded.transcriptSegments.map(\.text) == ["Transcript body"])
    #expect(!harness.fileManager.fileExists(atPath: harness.transcriptMarkdownURL(for: meeting.id).path))
}
```

- [ ] **Step 2: Run the transcription service tests and verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionServiceTests`

Expected: FAIL because the service still writes `transcript.md` and stores `transcriptFilePath`.

- [ ] **Step 3: Replace file artifact writes with database transcript persistence**

```swift
let storedTranscript = try await diarizer.diarize(
    TranscriptDiarizationRequest(audioFileURL: audioFileURL, result: result)
)

diarizationSimulationTask?.cancel()
diarizationSimulationTask = nil
progressCenter.updateDiarizationProgress(1.0, for: meetingID)

try meetingStore.completeTranscription(
    meetingID: meetingID,
    transcript: storedTranscript,
    transcriptPreview: storedTranscript.fullText.trimmingCharacters(in: .whitespacesAndNewlines),
    updatedAt: dateProvider()
)
```

- [ ] **Step 4: Reduce `TranscriptionArtifactWriter` to pure rendering helpers or remove it from the service initializer**

```swift
struct TranscriptionArtifactWriter {
    func renderMarkdown(from transcript: StoredTranscript) -> String {
        let speakerNames = Dictionary(uniqueKeysWithValues: transcript.speakers.map { ($0.id, $0.displayName) })
        var blocks: [(speakerName: String, lines: [String])] = []

        for segment in transcript.segments {
            let line = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let speakerName = speakerNames[segment.speakerID ?? ""] ?? "Speaker"
            if blocks.last?.speakerName == speakerName {
                blocks[blocks.count - 1].lines.append(line)
            } else {
                blocks.append((speakerName: speakerName, lines: [line]))
            }
        }

        return blocks.map { "## \($0.speakerName)\n" + $0.lines.joined(separator: "\n\n") }
            .joined(separator: "\n\n")
    }
}
```

- [ ] **Step 5: Update the tests to assert “no transcript file written”**

```swift
#expect(reloaded.transcriptSegments.map(\.speakerID) == ["speaker-1"])
#expect(reloaded.transcriptPreview == "Transcript body")
#expect(!harness.fileManager.fileExists(atPath: harness.transcriptMarkdownURL(for: meeting.id).path))
```

- [ ] **Step 6: Re-run the transcription tests and verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/TranscriptionServiceTests`

Expected: PASS for structured transcript persistence, replacement semantics, and progress behavior.

- [ ] **Step 7: Commit the transcription persistence change**

```bash
git add QuickMeeting/Services/Transcription/TranscriptionService.swift QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift QuickMeetingTests/TranscriptionServiceTests.swift
git commit -m "refactor: persist transcription results in database"
```

### Task 4: Switch transcript loading and speaker rename UI to DB-backed reads

**Files:**
- Modify: `QuickMeeting/Support/MeetingTranscriptContent.swift`
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeetingTests/MeetingTranscriptContentTests.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing transcript-content rendering test**

```swift
@Test
func storedTranscriptRendersMarkdownFromStructuredMeetingData() throws {
    let transcript = StoredTranscript(
        speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Masha")],
        segments: [TranscriptSegment(text: "Hello world", speakerID: "speaker-1")]
    )

    let content = loadMeetingTranscriptContent(from: transcript)

    #expect(content == .text("## Masha\nHello world"))
}
```

- [ ] **Step 2: Run the transcript-content tests and verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptContentTests -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: FAIL because transcript loading still expects a transcript file path and `AppViewModel` still renames by folder URL.

- [ ] **Step 3: Replace file-path transcript helpers with in-memory rendering**

```swift
func meetingTranscriptReloadKey(for meeting: Meeting) -> String {
    [
        meeting.id.uuidString,
        String(meeting.updatedAt.timeIntervalSinceReferenceDate),
        String(meeting.transcriptSegments.count),
        String(meeting.transcriptSpeakers.count)
    ].joined(separator: "|")
}

func loadMeetingTranscriptContent(from transcript: StoredTranscript?) -> MeetingTranscriptContent {
    guard let transcript else {
        return .notAvailable
    }

    let markdown = TranscriptionArtifactWriter().renderMarkdown(from: transcript)
    return markdown.isEmpty ? .notAvailable : .text(markdown)
}

func loadMeetingTranscriptSpeakers(from transcript: StoredTranscript?) -> MeetingTranscriptSpeakersContent {
    guard let transcript else {
        return .unavailable
    }
    return .available(transcript.speakers)
}
```

- [ ] **Step 4: Update `MeetingDetailView` and `AppViewModel` to use meeting IDs**

```swift
.task(id: meetingTranscriptReloadKey(for: meeting)) {
    let transcript = meeting.storedTranscript
    transcriptContent = loadMeetingTranscriptContent(from: transcript)
    switch loadMeetingTranscriptSpeakers(from: transcript) {
    case .available(let speakers):
        transcriptSpeakers = speakers
    case .unavailable:
        transcriptSpeakers = []
    }
}
```

```swift
func renameSpeaker(
    meetingID: UUID,
    speakerID: String,
    displayName: String
) async throws {
    do {
        _ = try meetingTranscriptStore.renameSpeaker(
            id: speakerID,
            to: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            in: meetingID
        )
        renameSpeakerErrorMessage = nil
    } catch {
        renameSpeakerErrorMessage = error.localizedDescription
        throw error
    }
}
```

- [ ] **Step 5: Update UI assertions to drop the transcript-file sidebar section**

```swift
if meeting.storedTranscript != nil {
    LabeledContent("Transcript", value: "Stored in database")
}
```

- [ ] **Step 6: Re-run the transcript content and view model tests**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptContentTests -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: PASS for in-memory transcript rendering and DB-backed rename flow.

- [ ] **Step 7: Commit the transcript read-path conversion**

```bash
git add QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/ViewModels/AppViewModel.swift QuickMeetingTests/MeetingTranscriptContentTests.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "refactor: render meeting transcripts from database state"
```

### Task 5: Finish integration, update app wiring, and revise docs

**Files:**
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `docs/quickmeeting-architecture-design.md`
- Test: `QuickMeetingTests/MeetingStoreTests.swift`
- Test: `QuickMeetingTests/MeetingTranscriptStoreTests.swift`
- Test: `QuickMeetingTests/MeetingTranscriptContentTests.swift`
- Test: `QuickMeetingTests/TranscriptionServiceTests.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Update app composition to inject the DB-backed transcript store**

```swift
let meetingStore = MeetingStore(modelContext: modelContext)
let meetingTranscriptStore = MeetingTranscriptStore(
    meetingStore: meetingStore,
    dateProvider: Date.init
)

let appViewModel = AppViewModel(
    meetingStore: meetingStore,
    meetingFileStore: meetingFileStore,
    recordingService: recordingService,
    transcriptionService: transcriptionService,
    transcriptionProgressCenter: progressCenter,
    meetingTranscriptStore: meetingTranscriptStore
)
```

- [ ] **Step 2: Update the architecture doc to match the new storage boundary**

```markdown
### Storage Model

- SwiftData stores meeting metadata and canonical transcript structure.
- The filesystem stores only the canonical `audio.wav` meeting recording.
- Rendered transcript markdown is derived on demand for UI display or future export.
```

- [ ] **Step 3: Run the full focused regression suite**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests -only-testing:QuickMeetingTests/MeetingTranscriptContentTests -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: PASS for all transcript, meeting persistence, transcription, and view-model tests.

- [ ] **Step 4: Run a broader app smoke test**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`

Expected: PASS or a short actionable list of unrelated failures to triage separately.

- [ ] **Step 5: Commit the wiring and documentation cleanup**

```bash
git add QuickMeeting/QuickMeetingApp.swift docs/quickmeeting-architecture-design.md
git commit -m "docs: align app storage architecture with database transcripts"
```

## Self-Review

### Spec coverage

- Aggregate root and schema change: covered by Task 1.
- `MeetingStore` as persistence boundary: covered by Task 2.
- Transcription DB writes and no transcript files: covered by Task 3.
- UI rendering from structured transcript data and speaker rename flow: covered by Task 4.
- App wiring and architecture docs: covered by Task 5.
- No migration work: intentionally excluded from all tasks.

### Placeholder scan

- No `TODO`, `TBD`, or “similar to above” shortcuts remain.
- Each test/run/commit step includes explicit commands and expected outcomes.
- Each code step includes concrete signatures and representative code.

### Type consistency

- `Meeting.completeTranscription(transcript:transcriptPreview:updatedAt:)` is used consistently across tasks.
- `Meeting.storedTranscript`, `transcriptSpeakers`, and `transcriptSegments` are referenced consistently.
- `MeetingTranscriptStoring.renameSpeaker(id:to:in:)` consistently accepts a `meetingID`.
