**Goal:** Add a bundled sidecar-backed transcription service that becomes the app's default manual transcription path while preserving the existing native implementation in the codebase.

**Architecture:** Add a new `SidecarTranscriptionService` behind the existing `TranscriptionServicing` boundary, plus small helper types for sidecar event decoding and process launching. Wire the new service into `QuickMeetingApp`, bundle the full `dist/example` payload with the app, and cover the behavior with focused service and decoder tests before touching runtime wiring.

**Tech Stack:** Swift, SwiftData, Foundation `Process`/`Pipe`, Swift Testing, Xcode project resources, `xcodebuild`

---

## File Map

### Create

- `QuickMeeting/Services/Transcription/SidecarTranscriptionEvent.swift`
  Purpose: Define the decoded sidecar stdout event types and payload structures.
- `QuickMeeting/Services/Transcription/SidecarTranscriptionEventDecoder.swift`
  Purpose: Parse newline-delimited JSON into typed sidecar events.
- `QuickMeeting/Services/Transcription/SidecarProcessLaunching.swift`
  Purpose: Define the small boundary around launching the bundled sidecar and streaming lines.
- `QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift`
  Purpose: Implement executable resolution, environment setup, process execution, and stdout streaming with `Process`.
- `QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift`
  Purpose: Orchestrate meeting validation, progress tracking, sidecar execution, transcript mapping, and persistence.
- `QuickMeetingTests/SidecarTranscriptionEventDecoderTests.swift`
  Purpose: Verify JSON decoding, malformed-line behavior, and payload mapping.
- `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`
  Purpose: Verify sidecar orchestration behavior without running the real executable.

### Modify

- `QuickMeeting/QuickMeetingApp.swift`
  Purpose: Register the sidecar service as the default `transcriptionService`.
- `QuickMeeting.xcodeproj/project.pbxproj`
  Purpose: Bundle the full `dist/example` payload so the app product contains the executable and sibling `_internal` directory.

## Task 1: Add the sidecar stdout contract and decoder

**Files:**
- Create: `QuickMeeting/Services/Transcription/SidecarTranscriptionEvent.swift`
- Create: `QuickMeeting/Services/Transcription/SidecarTranscriptionEventDecoder.swift`
- Test: `QuickMeetingTests/SidecarTranscriptionEventDecoderTests.swift`

- [ ] **Step 1: Write the failing decoder tests**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct SidecarTranscriptionEventDecoderTests {
    @Test
    func decodesCompletedEventWithSpeakersAndSegments() throws {
        let line = """
        {"status":"completed","speakers":[{"id":"SPEAKER_00","matched_id":null,"probability":null,"centroid":null}],"segments":[{"speaker":"SPEAKER_00","start":0.0,"end":2.481,"text":"Hello everyone"}]}
        """

        let event = try SidecarTranscriptionEventDecoder().decode(line: line)

        guard case .completed(let payload) = event else {
            Issue.record("Expected completed event")
            return
        }
        #expect(payload.speakers.map(\.id) == ["SPEAKER_00"])
        #expect(payload.segments.map(\.text) == ["Hello everyone"])
    }

    @Test
    func returnsNilForMalformedJsonLine() throws {
        let event = try SidecarTranscriptionEventDecoder().decode(line: "not json")
        #expect(event == nil)
    }

    @Test
    func decodesDiarizationProgressAsPercentInteger() throws {
        let line = #"{"status":"diarization","step":"segmentation","percent":15}"#

        let event = try SidecarTranscriptionEventDecoder().decode(line: line)

        guard case .diarization(let payload) = event else {
            Issue.record("Expected diarization event")
            return
        }
        #expect(payload.step == "segmentation")
        #expect(payload.percent == 15)
    }
}
```

- [ ] **Step 2: Run the focused decoder tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionEventDecoderTests
```

Expected: FAIL because `SidecarTranscriptionEventDecoder` and its event types do not exist yet.

- [ ] **Step 3: Add the minimal event and decoder implementation**

```swift
// QuickMeeting/Services/Transcription/SidecarTranscriptionEvent.swift
import Foundation

enum SidecarTranscriptionEvent: Equatable {
    case running
    case downloading(SidecarDownloadProgress)
    case transcribing(SidecarPercentProgress)
    case diarization(SidecarDiarizationProgress)
    case completed(SidecarCompletedPayload)
    case error(SidecarErrorPayload)
}

struct SidecarDownloadProgress: Codable, Equatable {
    let percent: Int
    let file: String?
    let bytesDownloaded: Int?
    let bytesTotal: Int?
}

struct SidecarPercentProgress: Codable, Equatable {
    let percent: Int
}

struct SidecarDiarizationProgress: Codable, Equatable {
    let step: String
    let percent: Int
}

struct SidecarCompletedPayload: Codable, Equatable {
    let speakers: [SidecarCompletedSpeaker]
    let segments: [SidecarCompletedSegment]
}

struct SidecarCompletedSpeaker: Codable, Equatable {
    let id: String
    let matchedID: String?
    let probability: Double?
    let centroid: [Double]?

    enum CodingKeys: String, CodingKey {
        case id
        case matchedID = "matched_id"
        case probability
        case centroid
    }
}

struct SidecarCompletedSegment: Codable, Equatable {
    let speaker: String
    let start: Double
    let end: Double
    let text: String
}

struct SidecarErrorPayload: Codable, Equatable {
    let reason: String
}
```

```swift
// QuickMeeting/Services/Transcription/SidecarTranscriptionEventDecoder.swift
import Foundation

struct SidecarTranscriptionEventDecoder {
    private let decoder = JSONDecoder()

    func decode(line: String) throws -> SidecarTranscriptionEvent? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }

        let envelope: StatusEnvelope
        do {
            envelope = try decoder.decode(StatusEnvelope.self, from: data)
        } catch {
            return nil
        }

        switch envelope.status {
        case "running":
            return .running
        case "downloading":
            return .downloading(try decoder.decode(DownloadingEnvelope.self, from: data).progress)
        case "transcribing":
            return .transcribing(try decoder.decode(TranscribingEnvelope.self, from: data).progress)
        case "diarization":
            return .diarization(try decoder.decode(DiarizationEnvelope.self, from: data).progress)
        case "completed":
            return .completed(try decoder.decode(CompletedEnvelope.self, from: data).payload)
        case "error":
            return .error(try decoder.decode(ErrorEnvelope.self, from: data).payload)
        default:
            return nil
        }
    }
}

private struct StatusEnvelope: Codable { let status: String }
private struct DownloadingEnvelope: Codable {
    let status: String
    let percent: Int
    let file: String?
    let bytesDownloaded: Int?
    let bytesTotal: Int?
    var progress: SidecarDownloadProgress {
        SidecarDownloadProgress(
            percent: percent,
            file: file,
            bytesDownloaded: bytesDownloaded,
            bytesTotal: bytesTotal
        )
    }
    enum CodingKeys: String, CodingKey {
        case status, percent, file, bytesTotal
        case bytesDownloaded = "bytes_downloaded"
    }
}
private struct TranscribingEnvelope: Codable {
    let status: String
    let percent: Int
    var progress: SidecarPercentProgress { SidecarPercentProgress(percent: percent) }
}
private struct DiarizationEnvelope: Codable {
    let status: String
    let step: String
    let percent: Int
    var progress: SidecarDiarizationProgress { SidecarDiarizationProgress(step: step, percent: percent) }
}
private struct CompletedEnvelope: Codable {
    let status: String
    let speakers: [SidecarCompletedSpeaker]
    let segments: [SidecarCompletedSegment]
    var payload: SidecarCompletedPayload { SidecarCompletedPayload(speakers: speakers, segments: segments) }
}
private struct ErrorEnvelope: Codable {
    let status: String
    let reason: String
    var payload: SidecarErrorPayload { SidecarErrorPayload(reason: reason) }
}
```

- [ ] **Step 4: Run the focused decoder tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionEventDecoderTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/SidecarTranscriptionEvent.swift QuickMeeting/Services/Transcription/SidecarTranscriptionEventDecoder.swift QuickMeetingTests/SidecarTranscriptionEventDecoderTests.swift
git commit -m "test: add sidecar event decoding"
```

## Task 2: Add the sidecar orchestration service behind `TranscriptionServicing`

**Files:**
- Create: `QuickMeeting/Services/Transcription/SidecarProcessLaunching.swift`
- Create: `QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift`
- Test: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing service tests**

```swift
import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct SidecarTranscriptionServiceTests {
    @Test
    func transcribeCompletedEventPersistsTranscriptAndCompletesMeeting() async throws {
        let harness = try SidecarTranscriptionHarness()
        let meeting = try harness.createRecordedMeeting()
        await harness.launcher.setResult(.success([
            #"{"status":"running"}"#,
            #"{"status":"transcribing","percent":40}"#,
            #"{"status":"diarization","step":"segmentation","percent":100}"#,
            #"{"status":"completed","speakers":[{"id":"SPEAKER_00","matched_id":null,"probability":null,"centroid":null}],"segments":[{"speaker":"SPEAKER_00","start":0.0,"end":1.5,"text":"Hello"}]}"#
        ]))

        try await harness.service.transcribe(meetingID: meeting.id)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .completed)
        #expect(reloaded.transcriptPreview == "Hello")
        #expect(reloaded.transcriptSpeakers.map(\.displayName) == ["Speaker 1"])
        #expect(reloaded.transcriptSegments.map(\.speakerID) == ["SPEAKER_00"])
        #expect(harness.progressCenter.progress(for: meeting.id) == nil)
        #expect(harness.progressCenter.diarizationProgress(for: meeting.id) == nil)
    }

    @Test
    func transcribeErrorEventMarksMeetingFailed() async throws {
        let harness = try SidecarTranscriptionHarness()
        let meeting = try harness.createRecordedMeeting()
        await harness.launcher.setResult(.failure(.sidecarReported("ffmpeg failed")))

        await #expect(throws: SidecarTranscriptionServiceError.sidecarFailed("ffmpeg failed")) {
            try await harness.service.transcribe(meetingID: meeting.id)
        }

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .failed)
    }

    @Test
    func transcribeRejectsSecondJobWhileFirstIsActive() async throws {
        let harness = try SidecarTranscriptionHarness()
        let firstMeeting = try harness.createRecordedMeeting()
        let secondMeeting = try harness.createRecordedMeeting()
        await harness.launcher.suspendNextRun()

        let task = Task { try await harness.service.transcribe(meetingID: firstMeeting.id) }
        await harness.launcher.waitForSuspendedRun()

        await #expect(throws: TranscriptionServiceError.transcriptionAlreadyActive) {
            try await harness.service.transcribe(meetingID: secondMeeting.id)
        }

        await harness.launcher.resume(with: .success([#"{"status":"completed","speakers":[],"segments":[]}"#]))
        try await task.value
    }
}
```

- [ ] **Step 2: Run the focused service tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: FAIL because the launcher boundary, service, and harness fakes do not exist yet.

- [ ] **Step 3: Add the launcher boundary and the minimal sidecar service**

```swift
// QuickMeeting/Services/Transcription/SidecarProcessLaunching.swift
import Foundation

struct SidecarLaunchRequest: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
}

enum SidecarLaunchError: Error, Equatable {
    case executableMissing
    case launchFailed(String)
    case terminatedWithoutTerminalEvent
    case sidecarReported(String)
}

protocol SidecarProcessLaunching: Sendable {
    func run(_ request: SidecarLaunchRequest) async throws -> [String]
}
```

```swift
// QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift
import Foundation

enum SidecarTranscriptionServiceError: LocalizedError, Equatable {
    case bundledExecutableMissing
    case sidecarFailed(String)
    case invalidCompletedPayload

    var errorDescription: String? {
        switch self {
        case .bundledExecutableMissing:
            return "Bundled transcription helper is missing."
        case .sidecarFailed(let reason):
            return reason
        case .invalidCompletedPayload:
            return "Transcription helper returned an invalid result."
        }
    }
}

@MainActor
final class SidecarTranscriptionService: TranscriptionServicing {
    private let meetingStore: MeetingStore
    private let progressCenter: TranscriptionProgressCenter
    private let launcher: any SidecarProcessLaunching
    private let eventDecoder: SidecarTranscriptionEventDecoder
    private let executableURLProvider: @Sendable () -> URL?
    private let hfTokenProvider: @Sendable () -> String
    private let hfHomeURLProvider: @Sendable () -> URL
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private var activeMeetingID: UUID?

    init(
        meetingStore: MeetingStore,
        progressCenter: TranscriptionProgressCenter,
        launcher: any SidecarProcessLaunching,
        eventDecoder: SidecarTranscriptionEventDecoder = SidecarTranscriptionEventDecoder(),
        executableURLProvider: @escaping @Sendable () -> URL?,
        hfTokenProvider: @escaping @Sendable () -> String,
        hfHomeURLProvider: @escaping @Sendable () -> URL,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.meetingStore = meetingStore
        self.progressCenter = progressCenter
        self.launcher = launcher
        self.eventDecoder = eventDecoder
        self.executableURLProvider = executableURLProvider
        self.hfTokenProvider = hfTokenProvider
        self.hfHomeURLProvider = hfHomeURLProvider
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    func transcribe(meetingID: UUID) async throws {
        guard activeMeetingID == nil else {
            throw TranscriptionServiceError.transcriptionAlreadyActive
        }

        let meeting = try meetingStore.fetchMeeting(id: meetingID)
        let status = try meeting.status
        guard status == .recorded || status == .failed || status == .completed else {
            throw TranscriptionServiceError.meetingNotTranscribable
        }

        let audioFileURL = URL(fileURLWithPath: meeting.audioFilePath)
        guard fileManager.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionServiceError.audioFileMissing
        }

        guard let executableURL = executableURLProvider() else {
            throw SidecarTranscriptionServiceError.bundledExecutableMissing
        }

        activeMeetingID = meetingID
        try meetingStore.startTranscription(meetingID: meetingID, updatedAt: dateProvider())
        progressCenter.startTracking(meetingID: meetingID)

        defer {
            progressCenter.finishTracking(meetingID: meetingID)
            activeMeetingID = nil
        }

        do {
            let lines = try await launcher.run(
                SidecarLaunchRequest(
                    executableURL: executableURL,
                    arguments: ["--input-file", audioFileURL.path, "--hf-token", hfTokenProvider()],
                    environment: ["HF_HOME": hfHomeURLProvider().path]
                )
            )

            let transcript = try apply(lines: lines, meetingID: meetingID)
            try meetingStore.completeTranscription(
                meetingID: meetingID,
                transcript: transcript,
                transcriptPreview: transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                updatedAt: dateProvider()
            )
        } catch {
            try? meetingStore.failTranscription(meetingID: meetingID, updatedAt: dateProvider())
            throw map(error)
        }
    }

    private func apply(lines: [String], meetingID: UUID) throws -> StoredTranscript {
        var completed: SidecarCompletedPayload?

        for line in lines {
            guard let event = try eventDecoder.decode(line: line) else { continue }
            switch event {
            case .running:
                continue
            case .downloading(let progress), .transcribing(let progress):
                progressCenter.updateProgress(Double(progress.percent) / 100, for: meetingID)
            case .diarization(let progress):
                if progressCenter.diarizationProgress(for: meetingID) == nil {
                    progressCenter.startDiarizationTracking(meetingID: meetingID)
                }
                progressCenter.updateDiarizationProgress(Double(progress.percent) / 100, for: meetingID)
            case .completed(let payload):
                completed = payload
            case .error(let payload):
                throw SidecarLaunchError.sidecarReported(payload.reason)
            }
        }

        guard let payload = completed else {
            throw SidecarLaunchError.terminatedWithoutTerminalEvent
        }

        return makeStoredTranscript(from: payload)
    }

    private func makeStoredTranscript(from payload: SidecarCompletedPayload) -> StoredTranscript {
        let orderedSpeakerIDs = payload.segments.map(\.speaker).reduce(into: [String]()) { result, speakerID in
            if !result.contains(speakerID) {
                result.append(speakerID)
            }
        }
        let speakers = orderedSpeakerIDs.enumerated().map { index, speakerID in
            TranscriptSpeaker(id: speakerID, displayName: "Speaker \(index + 1)")
        }
        let segments = payload.segments.map { segment in
            TranscriptSegment(
                text: segment.text,
                startTime: segment.start,
                endTime: segment.end,
                speakerID: segment.speaker
            )
        }
        return StoredTranscript(speakers: speakers, segments: segments)
    }

    private func map(_ error: Error) -> Error {
        switch error {
        case SidecarLaunchError.executableMissing:
            return SidecarTranscriptionServiceError.bundledExecutableMissing
        case SidecarLaunchError.sidecarReported(let reason):
            return SidecarTranscriptionServiceError.sidecarFailed(reason)
        default:
            return error
        }
    }
}
```

- [ ] **Step 4: Run the focused service tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/SidecarProcessLaunching.swift QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift QuickMeetingTests/SidecarTranscriptionServiceTests.swift
git commit -m "feat: add sidecar transcription service"
```

## Task 3: Implement the real process launcher and bundle-aware path resolution

**Files:**
- Create: `QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift`
- Modify: `QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift`
- Test: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing launcher-focused tests**

```swift
@Test
func transcribePassesExecutableArgumentsAndHFHomeToLauncher() async throws {
    let harness = try SidecarTranscriptionHarness()
    let meeting = try harness.createRecordedMeeting()
    let executableURL = URL(fileURLWithPath: "/tmp/QuickMeetingSidecar/example")
    let hfHomeURL = URL(fileURLWithPath: "/tmp/Application Support/QuickMeeting/HuggingFace")
    harness.executableURL = executableURL
    harness.hfHomeURL = hfHomeURL
    await harness.launcher.setResult(.success([#"{"status":"completed","speakers":[],"segments":[]}"#]))

    try await harness.service.transcribe(meetingID: meeting.id)

    let request = try await #require(harness.launcher.requests.first)
    #expect(request.executableURL == executableURL)
    #expect(request.arguments == ["--input-file", meeting.audioFilePath, "--hf-token", "hardcoded-token"])
    #expect(request.environment["HF_HOME"] == hfHomeURL.path)
}

@Test
func transcribeIgnoresMalformedLinesWhenCompletedEventArrivesLater() async throws {
    let harness = try SidecarTranscriptionHarness()
    let meeting = try harness.createRecordedMeeting()
    await harness.launcher.setResult(.success([
        "warning: not json",
        #"{"status":"completed","speakers":[],"segments":[]}"#
    ]))

    try await harness.service.transcribe(meetingID: meeting.id)

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(try reloaded.status == .completed)
}
```

- [ ] **Step 2: Run the focused service tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: FAIL because the request capture and real launcher behavior are not implemented yet.

- [ ] **Step 3: Add the real launcher and bundle path helpers**

```swift
// QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift
import Foundation

struct DefaultSidecarProcessLauncher: SidecarProcessLaunching {
    func run(_ request: SidecarLaunchRequest) async throws -> [String] {
        guard FileManager.default.fileExists(atPath: request.executableURL.path) else {
            throw SidecarLaunchError.executableMissing
        }

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(request.environment) { _, new in new }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(decoding: stdoutData, as: UTF8.self)
        let lines = stdout.split(whereSeparator: \.isNewline).map(String.init)

        if process.terminationStatus != 0 && lines.isEmpty {
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw SidecarLaunchError.launchFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return lines
    }
}
```

```swift
// QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift
private static func defaultExecutableURL() -> URL? {
    Bundle.main.resourceURL?
        .appendingPathComponent("example", isDirectory: true)
        .appendingPathComponent("example", isDirectory: false)
}

private static func defaultHFHomeURL(fileManager: FileManager) -> URL {
    let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return applicationSupportURL
        .appendingPathComponent("QuickMeeting", isDirectory: true)
        .appendingPathComponent("HuggingFace", isDirectory: true)
}
```

- [ ] **Step 4: Run the focused service tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift QuickMeetingTests/SidecarTranscriptionServiceTests.swift
git commit -m "feat: add bundled sidecar launcher"
```

## Task 4: Wire the sidecar service into the app and bundle the sidecar payload

**Files:**
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeeting.xcodeproj/project.pbxproj`
- Test: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing app wiring check**

```swift
@Test
func appUsesSidecarServiceAsDefaultTranscriptionService() {
    let progressCenter = TranscriptionProgressCenter()
    let meetingStore = MeetingStore(modelContext: ModelContext(try! ModelContainer(
        for: Schema([Meeting.self, PersistedTranscriptSpeaker.self, PersistedTranscriptSegment.self]),
        configurations: [ModelConfiguration(schema: Schema([Meeting.self, PersistedTranscriptSpeaker.self, PersistedTranscriptSegment.self]), isStoredInMemoryOnly: true)]
    )))

    let service = SidecarTranscriptionService(
        meetingStore: meetingStore,
        progressCenter: progressCenter,
        launcher: FakeSidecarProcessLauncher(),
        executableURLProvider: { URL(fileURLWithPath: "/tmp/example/example") },
        hfTokenProvider: { "hardcoded-token" },
        hfHomeURLProvider: { URL(fileURLWithPath: "/tmp/HuggingFace") }
    )

    #expect(service is any TranscriptionServicing)
}
```

- [ ] **Step 2: Run the focused sidecar tests to verify they still cover the wiring boundary**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: PASS before wiring changes; this is a confidence baseline before touching `QuickMeetingApp.swift` and the project file.

- [ ] **Step 3: Switch the app to the sidecar service and add the sidecar resources**

```swift
// QuickMeeting/QuickMeetingApp.swift
let transcriptionProgressCenter = TranscriptionProgressCenter()
let transcriptionService = SidecarTranscriptionService(
    meetingStore: meetingStore,
    progressCenter: transcriptionProgressCenter,
    launcher: DefaultSidecarProcessLauncher(),
    executableURLProvider: {
        Bundle.main.resourceURL?
            .appendingPathComponent("example", isDirectory: true)
            .appendingPathComponent("example", isDirectory: false)
    },
    hfTokenProvider: {
        "hardcoded-token"
    },
    hfHomeURLProvider: {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupportURL
            .appendingPathComponent("QuickMeeting", isDirectory: true)
            .appendingPathComponent("HuggingFace", isDirectory: true)
    }
)
```

```pbxproj
/* Add the full dist/example folder as a copied resource so the app bundle contains:
   QuickMeeting.app/Contents/Resources/example/example
   QuickMeeting.app/Contents/Resources/example/_internal/... */
```

- [ ] **Step 4: Run the focused sidecar tests, then the existing transcription regression suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: PASS.

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS, confirming the native code remains buildable and its tests still pass even though it is no longer the default wiring.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/QuickMeetingApp.swift QuickMeeting.xcodeproj/project.pbxproj
git commit -m "feat: make sidecar transcription the default"
```

## Task 5: Run final verification and document the bundle/runtime assumptions

**Files:**
- Modify: `docs/specs/2026-06-09-sidecar-transcription-design.md` only if implementation reveals a mismatch
- Test: `QuickMeetingTests/SidecarTranscriptionEventDecoderTests.swift`
- Test: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`
- Test: `QuickMeetingTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Run the full focused verification set**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionEventDecoderTests -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS with the new sidecar tests green and the legacy transcription tests still green.

- [ ] **Step 2: Sanity-check the app bundle resource layout**

Run:

```bash
xcodebuild -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-sidecar-build "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY="
```

Expected: `BUILD SUCCEEDED`.

Run:

```bash
find .derived-data-sidecar-build/Build/Products/Debug/QuickMeeting.app/Contents/Resources/example -maxdepth 2 | sed -n '1,40p'
```

Expected: output includes both `example` and `_internal`.

- [ ] **Step 3: Update docs only if the implementation differs from the approved spec**

```markdown
No doc changes needed if implementation matches the approved design.
```

- [ ] **Step 4: Commit any final doc or verification-driven adjustment**

```bash
git add docs/specs/2026-06-09-sidecar-transcription-design.md
git commit -m "docs: align sidecar transcription spec with implementation"
```

Only do this step if Step 3 changed the spec.

## Self-Review

- Spec coverage:
  Task 1 covers the stdout contract and malformed-line behavior.
  Task 2 covers service orchestration, status changes, transcript persistence, and progress updates.
  Task 3 covers real process launching, executable resolution, and `HF_HOME`.
  Task 4 covers default app wiring and bundling the full sidecar payload.
  Task 5 covers final verification and the bundle layout check.
- Placeholder scan:
  The only intentionally non-literal section is the `project.pbxproj` snippet note in Task 4 because the exact PBX object IDs must be generated from the existing project file structure during implementation.
- Type consistency:
  `SidecarTranscriptionEventDecoder`, `SidecarProcessLaunching`, `DefaultSidecarProcessLauncher`, and `SidecarTranscriptionService` names are used consistently across all tasks.
