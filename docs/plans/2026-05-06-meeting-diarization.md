**Goal:** Add diarized meeting transcription that writes a canonical `transcript.json`, renders a readable `transcript.md` grouped by speaker blocks, and lets users rename detected speakers without editing transcript text.

**Architecture:** Extend the existing transcription pipeline rather than replacing it. Keep orchestration in `TranscriptionService`, introduce a dedicated diarization boundary plus a focused `MeetingTranscriptStore` for sidecar reads and speaker renames, and make `TranscriptionArtifactWriter` the single place that renders both structured and Markdown artifacts from canonical transcript data.

**Tech Stack:** Swift, SwiftUI, SwiftData, Foundation, Testing, xcodebuild, WhisperKit

---

## File Map

### Create

- `QuickMeeting/Models/TranscriptSpeaker.swift`
  Purpose: Define the canonical speaker metadata persisted in `transcript.json`.
- `QuickMeeting/Models/StoredTranscript.swift`
  Purpose: Define the codable structured transcript sidecar model used by artifacts, loading, and rename flows.
- `QuickMeeting/Services/Transcription/TranscriptDiarizing.swift`
  Purpose: Define the diarization protocol and default no-op/fake-friendly implementation boundary.
- `QuickMeeting/Services/Transcription/MeetingTranscriptStore.swift`
  Purpose: Load and save `transcript.json`, update speaker names, and regenerate `transcript.md`.
- `QuickMeetingTests/MeetingTranscriptStoreTests.swift`
  Purpose: Verify sidecar loading, rename persistence, and Markdown regeneration behavior.
- `QuickMeetingTests/TranscriptMarkdownRenderingTests.swift`
  Purpose: Verify speaker-block Markdown rendering rules independently from the service.

### Modify

- `QuickMeeting/Models/TranscriptSegment.swift`
  Purpose: Keep `speakerID` required for persisted diarized segments and align domain types with sidecar storage.
- `QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift`
  Purpose: Replace `transcript.txt` output with `transcript.json` plus `transcript.md`, and derive previews from canonical transcript text.
- `QuickMeeting/Services/Transcription/WhisperTranscriptionBackend.swift`
  Purpose: Keep the transcription request/response boundary stable for the new diarization stage.
- `QuickMeeting/Services/Transcription/WhisperKitTranscriptionBackend.swift`
  Purpose: Continue producing timed segments for diarization input.
- `QuickMeeting/Services/Transcription/TranscriptionService.swift`
  Purpose: Insert diarization into the pipeline and route final persistence through the richer artifact layer.
- `QuickMeeting/Services/MeetingStore.swift`
  Purpose: Continue storing lifecycle state while now persisting the `transcript.md` path.
- `QuickMeeting/Support/MeetingTranscriptContent.swift`
  Purpose: Load Markdown transcript text, add helpers for structured transcript sidecar access, and keep transcript reload behavior stable.
- `QuickMeeting/Views/MeetingDetailView.swift`
  Purpose: Show rendered Markdown text, expose rename controls for detected speakers, and degrade gracefully when sidecar data is missing.
- `QuickMeeting/ViewModels/AppViewModel.swift`
  Purpose: Add the speaker rename action and wire rename errors/loading state into the meeting detail flow.
- `QuickMeeting/QuickMeetingApp.swift`
  Purpose: Wire the new diarizer and transcript store into the shared app dependency graph.
- `QuickMeetingTests/TranscriptionArtifactWriterTests.swift`
  Purpose: Update artifact tests for sidecar plus Markdown output.
- `QuickMeetingTests/TranscriptionServiceTests.swift`
  Purpose: Cover successful diarized transcription, retranscription replacement, and pipeline failure handling.
- `QuickMeetingTests/MeetingTranscriptContentTests.swift`
  Purpose: Update transcript loading tests for `.md` artifacts and sidecar-aware behavior.
- `QuickMeetingTests/AppViewModelTests.swift`
  Purpose: Cover the rename-speaker action and user-facing error state.
- `QuickMeetingTests/WhisperKitTranscriptionBackendTests.swift`
  Purpose: Keep backend tests aligned with the diarization-ready segment shape.

## Task 1: Add Structured Transcript Models

**Files:**
- Create: `QuickMeeting/Models/TranscriptSpeaker.swift`
- Create: `QuickMeeting/Models/StoredTranscript.swift`
- Modify: `QuickMeeting/Models/TranscriptSegment.swift`
- Test: `QuickMeetingTests/TranscriptMarkdownRenderingTests.swift`

- [ ] **Step 1: Write the failing domain-model test**

```swift
@Test
func storedTranscriptCapturesSpeakersAndSegments() throws {
    let transcript = StoredTranscript(
        speakers: [
            TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
            TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2"),
        ],
        segments: [
            TranscriptSegment(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                text: "Hello everyone.",
                startTime: 0,
                endTime: 1.2,
                speakerID: "speaker-1"
            ),
            TranscriptSegment(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                text: "Thanks, let's start.",
                startTime: 1.3,
                endTime: 2.4,
                speakerID: "speaker-2"
            ),
        ]
    )

    #expect(transcript.speakers.map(\.displayName) == ["Speaker 1", "Speaker 2"])
    #expect(transcript.segments.map(\.speakerID) == ["speaker-1", "speaker-2"])
    #expect(transcript.fullText == "Hello everyone.\nThanks, let's start.")
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptMarkdownRenderingTests
```

Expected: FAIL because `StoredTranscript` and `TranscriptSpeaker` do not exist yet.

- [ ] **Step 3: Add the structured transcript models**

```swift
// QuickMeeting/Models/TranscriptSpeaker.swift
import Foundation

struct TranscriptSpeaker: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var displayName: String
}
```

```swift
// QuickMeeting/Models/StoredTranscript.swift
import Foundation

struct StoredTranscript: Codable, Equatable, Sendable {
    var speakers: [TranscriptSpeaker]
    var segments: [TranscriptSegment]

    var fullText: String {
        segments
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
```

```swift
// QuickMeeting/Models/TranscriptSegment.swift
import Foundation

struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
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
```

- [ ] **Step 4: Run the focused test again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptMarkdownRenderingTests
```

Expected: PASS for the new domain-model test.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Models/TranscriptSpeaker.swift QuickMeeting/Models/StoredTranscript.swift QuickMeeting/Models/TranscriptSegment.swift QuickMeetingTests/TranscriptMarkdownRenderingTests.swift
git commit -m "feat: add structured transcript models"
```

## Task 2: Render Markdown And Structured Artifacts

**Files:**
- Modify: `QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift`
- Modify: `QuickMeetingTests/TranscriptionArtifactWriterTests.swift`
- Test: `QuickMeetingTests/TranscriptMarkdownRenderingTests.swift`

- [ ] **Step 1: Write the failing Markdown rendering test**

```swift
@Test
func renderMarkdownGroupsConsecutiveSegmentsBySpeaker() throws {
    let writer = TranscriptionArtifactWriter(fileManager: .default)
    let transcript = StoredTranscript(
        speakers: [
            TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
            TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2"),
        ],
        segments: [
            TranscriptSegment(text: "Hello everyone.", startTime: 0, endTime: 1, speakerID: "speaker-1"),
            TranscriptSegment(text: "One more point.", startTime: 1, endTime: 2, speakerID: "speaker-1"),
            TranscriptSegment(text: "Thanks, let's start.", startTime: 2, endTime: 3, speakerID: "speaker-2"),
        ]
    )

    let markdown = writer.renderMarkdown(from: transcript)

    #expect(markdown == """
    ## Speaker 1
    Hello everyone.
    
    One more point.
    
    ## Speaker 2
    Thanks, let's start.
    """)
}
```

- [ ] **Step 2: Run the focused artifact tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionArtifactWriterTests -only-testing:QuickMeetingTests/TranscriptMarkdownRenderingTests
```

Expected: FAIL because `renderMarkdown(from:)` and sidecar-writing support do not exist.

- [ ] **Step 3: Update the artifact writer to emit `transcript.json` and `transcript.md`**

```swift
// QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift
import Foundation

struct TranscriptionArtifacts: Equatable {
    let transcriptFileURL: URL
    let sidecarFileURL: URL
    let previewText: String
}

struct TranscriptionArtifactWriter {
    let fileManager: FileManager
    private let encoder = JSONEncoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writeArtifacts(
        for transcript: StoredTranscript,
        in meetingFolderURL: URL
    ) throws -> TranscriptionArtifacts {
        let sidecarFileURL = meetingFolderURL.appendingPathComponent("transcript.json")
        let transcriptFileURL = meetingFolderURL.appendingPathComponent("transcript.md")
        let sidecarData = try encoder.encode(transcript)
        let markdown = renderMarkdown(from: transcript)

        try sidecarData.write(to: sidecarFileURL, options: .atomic)
        try markdown.write(to: transcriptFileURL, atomically: true, encoding: .utf8)

        return TranscriptionArtifacts(
            transcriptFileURL: transcriptFileURL,
            sidecarFileURL: sidecarFileURL,
            previewText: makePreviewText(from: transcript)
        )
    }

    func renderMarkdown(from transcript: StoredTranscript) -> String {
        let resolvedNames = Dictionary(uniqueKeysWithValues: transcript.speakers.map { ($0.id, $0.displayName) })
        var blocks: [(speakerName: String, lines: [String])] = []

        for segment in transcript.segments {
            let line = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let speakerName = resolvedNames[segment.speakerID ?? ""] ?? "Speaker"

            if blocks.last?.speakerName == speakerName {
                blocks[blocks.count - 1].lines.append(line)
            } else {
                blocks.append((speakerName, [line]))
            }
        }

        return blocks
            .map { block in
                "## \(block.speakerName)\n" + block.lines.joined(separator: "\n\n")
            }
            .joined(separator: "\n\n")
    }

    func makePreviewText(from transcript: StoredTranscript) -> String {
        transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Update the artifact writer tests**

```swift
@Test
func writeArtifactsPersistsStructuredAndMarkdownTranscript() throws {
    let fileManager = FileManager.default
    let meetingFolderURL = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: meetingFolderURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: meetingFolderURL) }

    let writer = TranscriptionArtifactWriter(fileManager: fileManager)
    let transcript = StoredTranscript(
        speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
        segments: [TranscriptSegment(text: "Hello world", speakerID: "speaker-1")]
    )

    let artifacts = try writer.writeArtifacts(for: transcript, in: meetingFolderURL)

    #expect(artifacts.transcriptFileURL == meetingFolderURL.appendingPathComponent("transcript.md"))
    #expect(artifacts.sidecarFileURL == meetingFolderURL.appendingPathComponent("transcript.json"))
    #expect(try String(contentsOf: artifacts.transcriptFileURL) == "## Speaker 1\nHello world")
    #expect(artifacts.previewText == "Hello world")
}
```

- [ ] **Step 5: Run the focused artifact tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionArtifactWriterTests -only-testing:QuickMeetingTests/TranscriptMarkdownRenderingTests
```

Expected: PASS for Markdown rendering and dual-artifact persistence.

- [ ] **Step 6: Commit**

```bash
git add QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift QuickMeetingTests/TranscriptionArtifactWriterTests.swift QuickMeetingTests/TranscriptMarkdownRenderingTests.swift
git commit -m "feat: write structured and markdown transcripts"
```

## Task 3: Add The Diarization Boundary

**Files:**
- Create: `QuickMeeting/Services/Transcription/TranscriptDiarizing.swift`
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing diarization pipeline test**

```swift
@Test
func transcribeRecordedMeetingAssignsSpeakerIDsBeforeWritingArtifacts() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createRecordedMeeting()
    await harness.installDefaultModel(.small)
    await harness.backend.setResult(.success(
        TranscriptionResult(
            fullText: "Hello\nThanks",
            segments: [
                TranscriptSegment(text: "Hello", startTime: 0, endTime: 1),
                TranscriptSegment(text: "Thanks", startTime: 1, endTime: 2),
            ]
        )
    ))
    await harness.diarizer.setResult(.success(
        StoredTranscript(
            speakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
                TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2"),
            ],
            segments: [
                TranscriptSegment(text: "Hello", startTime: 0, endTime: 1, speakerID: "speaker-1"),
                TranscriptSegment(text: "Thanks", startTime: 1, endTime: 2, speakerID: "speaker-2"),
            ]
        )
    ))

    try await harness.service.transcribe(meetingID: meeting.id)

    let snapshot = await harness.diarizer.snapshot()
    #expect(snapshot.requests.count == 1)
    #expect(snapshot.requests.first?.result.segments.map(\.speakerID) == [nil, nil])
}
```

- [ ] **Step 2: Run the focused service tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: FAIL because the harness and service do not have a diarizer dependency.

- [ ] **Step 3: Add the diarization protocol and a deterministic default implementation**

```swift
// QuickMeeting/Services/Transcription/TranscriptDiarizing.swift
import Foundation

struct TranscriptDiarizationRequest: Sendable {
    let audioFileURL: URL
    let result: TranscriptionResult
}

protocol TranscriptDiarizing: Sendable {
    func diarize(_ request: TranscriptDiarizationRequest) async throws -> StoredTranscript
}

struct DefaultTranscriptDiarizer: TranscriptDiarizing {
    func diarize(_ request: TranscriptDiarizationRequest) async throws -> StoredTranscript {
        var speakerMap: [String: String] = [:]
        var orderedSpeakers: [TranscriptSpeaker] = []
        let diarizedSegments = request.result.segments.enumerated().map { index, segment in
            let speakerID = segment.speakerID ?? "speaker-1"

            if speakerMap[speakerID] == nil {
                let displayName = "Speaker \(orderedSpeakers.count + 1)"
                speakerMap[speakerID] = displayName
                orderedSpeakers.append(TranscriptSpeaker(id: speakerID, displayName: displayName))
            }

            if segment.speakerID == nil, index == 0, orderedSpeakers.isEmpty {
                orderedSpeakers.append(TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"))
            }

            return TranscriptSegment(
                id: segment.id,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                speakerID: speakerID
            )
        }

        let speakers = orderedSpeakers.isEmpty
            ? [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")]
            : orderedSpeakers

        let segments = diarizedSegments.map {
            TranscriptSegment(
                id: $0.id,
                text: $0.text,
                startTime: $0.startTime,
                endTime: $0.endTime,
                speakerID: $0.speakerID ?? speakers.first?.id
            )
        }

        return StoredTranscript(speakers: speakers, segments: segments)
    }
}
```

- [ ] **Step 4: Run the focused service tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: FAIL later in the service until `TranscriptionService` is wired to call the diarizer.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/TranscriptDiarizing.swift QuickMeetingTests/TranscriptionServiceTests.swift
git commit -m "feat: add transcript diarization boundary"
```

## Task 4: Insert Diarization Into TranscriptionService

**Files:**
- Modify: `QuickMeeting/Services/Transcription/TranscriptionService.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Add the failing dual-artifact service assertion**

```swift
@Test
func transcribeRecordedMeetingWritesMarkdownAndCompletesMeeting() async throws {
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
    #expect(reloaded.transcriptFilePath?.hasSuffix("/transcript.md") == true)
    let transcriptPath = try #require(reloaded.transcriptFilePath)
    #expect(try String(contentsOfFile: transcriptPath) == "## Speaker 1\nTranscript body")
}
```

- [ ] **Step 2: Run the focused service tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: FAIL because `TranscriptionService` still writes `TranscriptionResult` straight to `transcript.txt`.

- [ ] **Step 3: Wire the service through the diarizer and richer artifact writer**

```swift
// QuickMeeting/Services/Transcription/TranscriptionService.swift
@MainActor
final class TranscriptionService: TranscriptionServicing {
    private let meetingStore: MeetingStore
    private let modelStore: any WhisperModelStore
    private let modelSettingsStore: ModelSettingsStore
    private let backend: any WhisperTranscriptionBackend
    private let diarizer: any TranscriptDiarizing
    private let progressCenter: TranscriptionProgressCenter
    private let artifactWriter: TranscriptionArtifactWriter
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private var activeMeetingID: UUID?

    init(
        meetingStore: MeetingStore,
        modelStore: any WhisperModelStore,
        modelSettingsStore: ModelSettingsStore,
        backend: any WhisperTranscriptionBackend,
        diarizer: any TranscriptDiarizing,
        progressCenter: TranscriptionProgressCenter,
        artifactWriter: TranscriptionArtifactWriter? = nil,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.meetingStore = meetingStore
        self.modelStore = modelStore
        self.modelSettingsStore = modelSettingsStore
        self.backend = backend
        self.diarizer = diarizer
        self.progressCenter = progressCenter
        self.artifactWriter = artifactWriter ?? TranscriptionArtifactWriter(fileManager: fileManager)
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    func transcribe(meetingID: UUID) async throws {
        // keep the existing validation block

        let result = try await backend.transcribe(
            TranscriptionRequest(
                audioFileURL: audioFileURL,
                model: model,
                modelFolderURL: modelFolderURL,
                onProgress: { [progressCenter] progress in
                    Task { @MainActor in
                        progressCenter.updateProgress(progress, for: meetingID)
                    }
                }
            )
        )
        let storedTranscript = try await diarizer.diarize(
            TranscriptDiarizationRequest(audioFileURL: audioFileURL, result: result)
        )
        let artifacts = try artifactWriter.writeArtifacts(
            for: storedTranscript,
            in: audioFileURL.deletingLastPathComponent()
        )
        try meetingStore.completeTranscription(
            meetingID: meetingID,
            transcriptFileURL: artifacts.transcriptFileURL,
            transcriptPreview: artifacts.previewText,
            updatedAt: dateProvider()
        )
    }
}
```

- [ ] **Step 4: Wire the real app graph**

```swift
// QuickMeeting/QuickMeetingApp.swift
let transcriptionService = TranscriptionService(
    meetingStore: meetingStore,
    modelStore: modelStore,
    modelSettingsStore: modelSettingsStore,
    backend: WhisperKitTranscriptionBackend(),
    diarizer: DefaultTranscriptDiarizer(),
    progressCenter: transcriptionProgressCenter
)
```

- [ ] **Step 5: Run the focused service tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS for diarized transcription success, retranscription replacement, and failure cleanup tests.

- [ ] **Step 6: Commit**

```bash
git add QuickMeeting/Services/Transcription/TranscriptionService.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/TranscriptionServiceTests.swift
git commit -m "feat: diarize transcripts in transcription service"
```

## Task 5: Add MeetingTranscriptStore For Sidecar Reads And Renames

**Files:**
- Create: `QuickMeeting/Services/Transcription/MeetingTranscriptStore.swift`
- Create: `QuickMeetingTests/MeetingTranscriptStoreTests.swift`
- Modify: `QuickMeetingTests/TranscriptionArtifactWriterTests.swift`

- [ ] **Step 1: Write the failing rename test**

```swift
@Test
func renameSpeakerUpdatesSidecarAndRegeneratesMarkdown() throws {
    let fileManager = FileManager.default
    let meetingFolderURL = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: meetingFolderURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: meetingFolderURL) }

    let writer = TranscriptionArtifactWriter(fileManager: fileManager)
    let transcript = StoredTranscript(
        speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
        segments: [TranscriptSegment(text: "Hello world", speakerID: "speaker-1")]
    )
    _ = try writer.writeArtifacts(for: transcript, in: meetingFolderURL)

    let store = MeetingTranscriptStore(fileManager: fileManager, artifactWriter: writer)

    let updated = try store.renameSpeaker(
        id: "speaker-1",
        to: "Masha",
        in: meetingFolderURL
    )

    let markdown = try String(contentsOf: meetingFolderURL.appendingPathComponent("transcript.md"))
    #expect(updated.speakers.first?.displayName == "Masha")
    #expect(markdown == "## Masha\nHello world")
}
```

- [ ] **Step 2: Run the focused transcript-store tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests
```

Expected: FAIL because `MeetingTranscriptStore` does not exist.

- [ ] **Step 3: Implement the transcript store**

```swift
// QuickMeeting/Services/Transcription/MeetingTranscriptStore.swift
import Foundation

enum MeetingTranscriptStoreError: LocalizedError, Equatable {
    case sidecarMissing
    case speakerNotFound

    var errorDescription: String? {
        switch self {
        case .sidecarMissing:
            return "Transcript data is unavailable."
        case .speakerNotFound:
            return "Speaker could not be updated."
        }
    }
}

struct MeetingTranscriptStore {
    let fileManager: FileManager
    let artifactWriter: TranscriptionArtifactWriter
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        artifactWriter: TranscriptionArtifactWriter = TranscriptionArtifactWriter()
    ) {
        self.fileManager = fileManager
        self.artifactWriter = artifactWriter
    }

    func loadTranscript(in meetingFolderURL: URL) throws -> StoredTranscript {
        let sidecarURL = meetingFolderURL.appendingPathComponent("transcript.json")
        guard fileManager.fileExists(atPath: sidecarURL.path) else {
            throw MeetingTranscriptStoreError.sidecarMissing
        }

        let data = try Data(contentsOf: sidecarURL)
        return try decoder.decode(StoredTranscript.self, from: data)
    }

    @discardableResult
    func renameSpeaker(id: String, to displayName: String, in meetingFolderURL: URL) throws -> StoredTranscript {
        var transcript = try loadTranscript(in: meetingFolderURL)
        guard let index = transcript.speakers.firstIndex(where: { $0.id == id }) else {
            throw MeetingTranscriptStoreError.speakerNotFound
        }

        transcript.speakers[index].displayName = displayName
        _ = try artifactWriter.writeArtifacts(for: transcript, in: meetingFolderURL)
        return transcript
    }
}
```

- [ ] **Step 4: Run the focused transcript-store tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests
```

Expected: PASS for sidecar load and rename regeneration behavior.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/MeetingTranscriptStore.swift QuickMeetingTests/MeetingTranscriptStoreTests.swift
git commit -m "feat: add transcript sidecar store"
```

## Task 6: Load Markdown And Sidecar Data In Meeting Detail

**Files:**
- Modify: `QuickMeeting/Support/MeetingTranscriptContent.swift`
- Modify: `QuickMeetingTests/MeetingTranscriptContentTests.swift`
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`

- [ ] **Step 1: Write the failing `.md` transcript-loading test**

```swift
@Test
func readableMarkdownTranscriptFileReturnsText() throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let transcriptURL = rootURL.appendingPathComponent("transcript.md")
    try "## Speaker 1\nLine one".write(to: transcriptURL, atomically: true, encoding: .utf8)

    let content = try loadMeetingTranscriptContent(from: transcriptURL.path)

    #expect(content == .text("## Speaker 1\nLine one"))
}
```

- [ ] **Step 2: Run the focused transcript-content tests to verify they fail if extension-specific assumptions remain**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: FAIL if tests or helpers still hardcode `transcript.txt`.

- [ ] **Step 3: Add structured sidecar loading helper methods**

```swift
// QuickMeeting/Support/MeetingTranscriptContent.swift
import Foundation

enum MeetingTranscriptSpeakersContent: Equatable {
    case available([TranscriptSpeaker])
    case unavailable
}

func loadMeetingTranscriptSpeakers(
    from transcriptFilePath: String?,
    fileManager: FileManager = .default
) -> MeetingTranscriptSpeakersContent {
    guard let transcriptFilePath else {
        return .unavailable
    }

    let transcriptURL = URL(fileURLWithPath: transcriptFilePath)
    let meetingFolderURL = transcriptURL.deletingLastPathComponent()
    let store = MeetingTranscriptStore(fileManager: fileManager)

    do {
        let transcript = try store.loadTranscript(in: meetingFolderURL)
        return .available(transcript.speakers)
    } catch {
        return .unavailable
    }
}
```

- [ ] **Step 4: Update the meeting detail view to show speaker rename controls**

```swift
// QuickMeeting/Views/MeetingDetailView.swift
@State private var transcriptSpeakers: [TranscriptSpeaker] = []

.task(id: meetingDetailReloadKey(for: meeting)) {
    transcriptContent = (try? loadMeetingTranscriptContent(from: meeting.transcriptFilePath))
        ?? .unavailable(message: "Transcript file is unavailable.")

    switch loadMeetingTranscriptSpeakers(from: meeting.transcriptFilePath) {
    case .available(let speakers):
        transcriptSpeakers = speakers
    case .unavailable:
        transcriptSpeakers = []
    }
}

private var speakerSection: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Speakers")
            .font(.headline)

        if transcriptSpeakers.isEmpty {
            Text("Speaker data unavailable")
                .foregroundStyle(.secondary)
        } else {
            ForEach(transcriptSpeakers) { speaker in
                TextField(
                    "Speaker name",
                    text: Binding(
                        get: { speaker.displayName },
                        set: { _ in }
                    )
                )
            }
        }
    }
}
```

- [ ] **Step 5: Run the focused transcript-content tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: PASS for `.md` transcript reading and sidecar speaker-load helpers.

- [ ] **Step 6: Commit**

```bash
git add QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "feat: load markdown transcripts in meeting detail"
```

## Task 7: Add Rename-Speaker Actions In AppViewModel

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing rename action test**

```swift
@Test
func renameSpeakerUpdatesTranscriptArtifacts() async throws {
    let harness = try AppViewModelTestHarness()
    let meeting = try harness.createCompletedMeetingWithTranscript()
    let viewModel = AppViewModel(
        meetingStore: harness.meetingStore,
        meetingFileStore: harness.meetingFileStore,
        recordingService: harness.recordingService,
        transcriptionService: harness.transcriptionService,
        transcriptionProgressCenter: harness.transcriptionProgressCenter,
        recordingPermissions: harness.recordingPermissions,
        meetingTranscriptStore: harness.meetingTranscriptStore
    )

    try await viewModel.renameSpeaker(
        meetingID: meeting.id,
        speakerID: "speaker-1",
        displayName: "Masha"
    )

    let transcript = try harness.meetingTranscriptStore.loadTranscript(in: harness.folderURL(for: meeting.id))
    #expect(transcript.speakers.first?.displayName == "Masha")
}
```

- [ ] **Step 2: Run the focused `AppViewModel` tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: FAIL because `AppViewModel` does not yet expose a rename action or transcript-store dependency.

- [ ] **Step 3: Add the rename action**

```swift
// QuickMeeting/ViewModels/AppViewModel.swift
@Published private(set) var renameSpeakerErrorMessage: String?

private let meetingTranscriptStore: MeetingTranscriptStore

func renameSpeaker(meetingID: UUID, speakerID: String, displayName: String) async throws {
    let meeting = try meetingStore.fetchMeeting(id: meetingID)
    let meetingFolderURL = URL(fileURLWithPath: meeting.audioFilePath).deletingLastPathComponent()

    do {
        _ = try meetingTranscriptStore.renameSpeaker(
            id: speakerID,
            to: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            in: meetingFolderURL
        )
        renameSpeakerErrorMessage = nil
    } catch {
        renameSpeakerErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Speaker rename failed."
        throw error
    }
}
```

- [ ] **Step 4: Wire the dependency through the app graph**

```swift
// QuickMeeting/QuickMeetingApp.swift
let transcriptStore = MeetingTranscriptStore()

let appViewModel = AppViewModel(
    meetingStore: meetingStore,
    meetingFileStore: meetingFileStore,
    recordingService: recordingService,
    transcriptionService: transcriptionService,
    transcriptionProgressCenter: transcriptionProgressCenter,
    recordingPermissions: recordingPermissions,
    meetingTranscriptStore: transcriptStore
)
```

- [ ] **Step 5: Run the focused `AppViewModel` tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS for rename success and user-facing error propagation tests.

- [ ] **Step 6: Commit**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: add speaker rename action"
```

## Task 8: Connect Editable Speaker UI In Meeting Detail

**Files:**
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeeting/ContentView.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing UI-driven rename test**

```swift
@Test
func meetingDetailShowsSpeakerNamesForCompletedTranscript() async throws {
    let harness = try AppViewModelTestHarness()
    let meeting = try harness.createCompletedMeetingWithTranscript()
    let speakers = loadMeetingTranscriptSpeakers(from: meeting.transcriptFilePath)

    switch speakers {
    case .available(let resolved):
        #expect(resolved.map(\.displayName) == ["Speaker 1"])
    case .unavailable:
        Issue.record("Expected speakers to be available")
    }
}
```

- [ ] **Step 2: Run the focused tests to verify current behavior fails or is incomplete**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: FAIL or expose missing plumbing between the loaded speakers and the meeting detail UI.

- [ ] **Step 3: Thread rename callbacks into the detail view**

```swift
// QuickMeeting/Views/MeetingDetailView.swift
let onRenameSpeaker: (String, String) -> Void

private var speakerSection: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Speakers")
            .font(.headline)

        if transcriptSpeakers.isEmpty {
            Text("Speaker data unavailable")
                .foregroundStyle(.secondary)
        } else {
            ForEach(transcriptSpeakers) { speaker in
                TextField(
                    "Speaker name",
                    text: Binding(
                        get: { speaker.displayName },
                        set: { newValue in
                            onRenameSpeaker(speaker.id, newValue)
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }
        }
    }
}
```

- [ ] **Step 4: Thread the callback from `ContentView` through `AppViewModel`**

```swift
// QuickMeeting/ContentView.swift
MeetingDetailView(
    meeting: meeting,
    transcriptionProgress: appViewModel.transcriptionProgress(for: meeting.id),
    canDelete: appViewModel.canDeleteMeeting(meeting),
    canTranscribe: appViewModel.canTranscribeMeeting(meeting),
    onTranscribe: { appViewModel.transcribeMeeting(meeting) },
    onDelete: { appViewModel.deleteMeeting(meeting) },
    onRenameSpeaker: { speakerID, displayName in
        Task {
            try? await appViewModel.renameSpeaker(
                meetingID: meeting.id,
                speakerID: speakerID,
                displayName: displayName
            )
        }
    }
)
```

- [ ] **Step 5: Run the focused tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: PASS for loaded speaker availability and rename plumbing tests.

- [ ] **Step 6: Commit**

```bash
git add QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/ContentView.swift QuickMeetingTests/AppViewModelTests.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "feat: add editable speaker names in meeting detail"
```

## Task 9: Verify Failure Handling And Retranscription Replacement

**Files:**
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`
- Modify: `QuickMeetingTests/MeetingTranscriptStoreTests.swift`

- [ ] **Step 1: Write the failing artifact-pair failure test**

```swift
@Test
func transcribeFailureWhileWritingArtifactsMarksMeetingFailed() async throws {
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
    harness.artifactWriter.failWrites = true

    await #expect(throws: TestTranscriptionError.failed) {
        try await harness.service.transcribe(meetingID: meeting.id)
    }

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .failed)
}
```

- [ ] **Step 2: Run the focused failure tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests
```

Expected: FAIL because the harnesses do not yet simulate sidecar-write failures or rename rollback expectations.

- [ ] **Step 3: Add rename failure coverage**

```swift
@Test
func renameSpeakerFailsWhenSidecarIsMissing() throws {
    let fileManager = FileManager.default
    let meetingFolderURL = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: meetingFolderURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: meetingFolderURL) }

    let store = MeetingTranscriptStore(fileManager: fileManager)

    #expect(throws: MeetingTranscriptStoreError.sidecarMissing) {
        try store.renameSpeaker(id: "speaker-1", to: "Masha", in: meetingFolderURL)
    }
}
```

- [ ] **Step 4: Run the focused failure tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests
```

Expected: PASS for diarization failure, artifact-write failure, retranscription replacement, and rename-missing-sidecar coverage.

- [ ] **Step 5: Commit**

```bash
git add QuickMeetingTests/TranscriptionServiceTests.swift QuickMeetingTests/MeetingTranscriptStoreTests.swift
git commit -m "test: cover diarization failure handling"
```

## Task 10: Run Full Verification

**Files:**
- Modify: `QuickMeetingTests/WhisperKitTranscriptionBackendTests.swift`
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`
- Modify: `QuickMeetingTests/TranscriptionArtifactWriterTests.swift`
- Modify: `QuickMeetingTests/MeetingTranscriptContentTests.swift`
- Modify: `QuickMeetingTests/MeetingTranscriptStoreTests.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Run the full focused diarization suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/WhisperKitTranscriptionBackendTests -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/TranscriptionArtifactWriterTests -only-testing:QuickMeetingTests/MeetingTranscriptContentTests -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS for the diarization pipeline, artifact rendering, rename flow, and UI-facing behavior.

- [ ] **Step 2: Run the broader app regression suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-diarization "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY="
```

Expected: PASS or only unrelated pre-existing failures. If unrelated failures appear, note them before any follow-up change.

- [ ] **Step 3: Commit the final integrated work**

```bash
git add QuickMeeting QuickMeetingTests
git commit -m "feat: add diarized meeting transcripts"
```

## Spec Coverage Check

- Structured transcript sidecar as canonical data: covered by Tasks 1, 2, and 5.
- Markdown speaker-block artifact: covered by Tasks 2 and 6.
- Diarization stage inside the existing pipeline: covered by Tasks 3 and 4.
- Speaker-name-only editing: covered by Tasks 5, 7, and 8.
- Retranscription replacing structured and Markdown artifacts: covered by Tasks 4 and 9.
- Graceful failure handling and missing-sidecar behavior: covered by Tasks 6 and 9.

## Placeholder Scan

- No `TODO`, `TBD`, or deferred implementation markers remain.
- Each code-changing task includes concrete file paths, sample code, and an execution command.
- Each verification step names the exact `xcodebuild` command to run.

## Type Consistency Check

- `StoredTranscript`, `TranscriptSpeaker`, `TranscriptSegment`, and `MeetingTranscriptStore` are named consistently across tasks.
- The app-facing rename flow always uses `renameSpeaker(meetingID:speakerID:displayName:)`.
- Artifact paths consistently target `transcript.json` and `transcript.md`.
