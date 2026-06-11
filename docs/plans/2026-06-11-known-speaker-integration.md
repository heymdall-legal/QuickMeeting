**Goal:** Integrate the sidecar's known-speaker recognition into QuickMeeting so transcripts can persist per-speaker centroids, auto-apply matched names on future runs, and learn from manual speaker renames.

**Architecture:** Extend meeting-local transcript speakers with provenance and centroid metadata, then add a separate SwiftData-backed global known-speaker store in the same model container. Update the sidecar transcription pipeline to export known speakers before launch, map `matched_id` results back into meeting-local speakers on completion, and trigger best-effort centroid enrollment after accepted matches and manual renames.

**Tech Stack:** Swift, SwiftData, Foundation, Swift Testing, Xcode, sidecar Python process launch

---

## File Map

### Create

- `QuickMeeting/Models/TranscriptSpeakerLabelSource.swift`
  Purpose: Define transcript speaker provenance values: `generic`, `userAssigned`, and `bankMatched`.
- `QuickMeeting/Models/PersistedKnownSpeaker.swift`
  Purpose: SwiftData model for global known speakers with stable ID, display name, timestamps, and centroid relationship.
- `QuickMeeting/Models/PersistedKnownSpeakerCentroid.swift`
  Purpose: SwiftData model for ordered centroid history with source meeting metadata and creation time.
- `QuickMeeting/Services/Transcription/KnownSpeakerStore.swift`
  Purpose: Persistence boundary for loading, finding, creating, and pruning global known speakers.
- `QuickMeeting/Services/Transcription/KnownSpeakerJSONWriter.swift`
  Purpose: Export known speakers into the sidecar's `{ id, centroids }` JSON payload.
- `QuickMeeting/Services/Transcription/SpeakerRecognitionMapper.swift`
  Purpose: Convert sidecar completed payload into enriched `TranscriptSpeaker` values with auto-match rules.
- `QuickMeeting/Services/Transcription/KnownSpeakerEnrollmentService.swift`
  Purpose: Best-effort centroid enrollment after auto-match and manual rename.
- `QuickMeetingTests/KnownSpeakerStoreTests.swift`
  Purpose: Verify exact-name reuse, new known-speaker creation, and oldest-centroid pruning.
- `QuickMeetingTests/KnownSpeakerJSONWriterTests.swift`
  Purpose: Verify export JSON shape and empty-store omission behavior.
- `QuickMeetingTests/SpeakerRecognitionMapperTests.swift`
  Purpose: Verify `probability > 0.8` auto-match logic and generic fallback.
- `QuickMeetingTests/AppViewModelTests.swift`
  Purpose: Verify rename persistence remains successful even when enrollment fails.

### Modify

- `QuickMeeting/Models/TranscriptSpeaker.swift`
  Purpose: Add provenance, matched known-speaker ID, and centroid metadata to meeting-local speakers.
- `QuickMeeting/Models/PersistedTranscriptSpeaker.swift`
  Purpose: Persist the richer transcript speaker fields in SwiftData.
- `QuickMeeting/Models/Meeting.swift`
  Purpose: Rebuild `StoredTranscript` using the enriched persisted speaker model.
- `QuickMeeting/Services/MeetingStore.swift`
  Purpose: Persist user-assigned rename metadata during meeting-local rename.
- `QuickMeeting/Services/Transcription/MeetingTranscriptStore.swift`
  Purpose: Return the renamed transcript with the new speaker metadata intact.
- `QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift`
  Purpose: Export known speakers before launch, pass `--known-speakers-file`, map sidecar speaker payloads, and append matched centroids best-effort.
- `QuickMeeting/QuickMeetingApp.swift`
  Purpose: Register new SwiftData models and wire known-speaker services into app dependencies.
- `QuickMeeting/ViewModels/AppViewModel.swift`
  Purpose: Trigger best-effort known-speaker enrollment after a successful manual rename.
- `QuickMeetingTests/MeetingStoreTests.swift`
  Purpose: Verify rename updates transcript speaker provenance and matched ID handling.
- `QuickMeetingTests/MeetingTranscriptStoreTests.swift`
  Purpose: Verify rename returns enriched transcript speakers, not just display names.
- `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`
  Purpose: Verify sidecar request args and persisted transcript speaker metadata.

## Task 1: Extend meeting-local transcript speakers with provenance and centroids

**Files:**
- Create: `QuickMeeting/Models/TranscriptSpeakerLabelSource.swift`
- Modify: `QuickMeeting/Models/TranscriptSpeaker.swift`
- Modify: `QuickMeeting/Models/PersistedTranscriptSpeaker.swift`
- Modify: `QuickMeeting/Models/Meeting.swift`
- Modify: `QuickMeeting/Services/MeetingStore.swift`
- Test: `QuickMeetingTests/MeetingStoreTests.swift`
- Test: `QuickMeetingTests/MeetingTranscriptStoreTests.swift`

- [ ] **Step 1: Write the failing meeting-store test for enriched transcript speaker persistence**

```swift
@Test
func renameSpeakerMarksSpeakerAsUserAssignedAndClearsMatchedKnownSpeakerID() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.createCompletedMeeting(
        transcript: StoredTranscript(
            speakers: [
                TranscriptSpeaker(
                    id: "speaker-1",
                    displayName: "Alice",
                    labelSource: .bankMatched,
                    matchedKnownSpeakerID: "known-alice",
                    centroid: [0.1, 0.2, 0.3]
                )
            ],
            segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
        ),
        transcriptPreview: "Hello"
    )

    try harness.store.renameSpeaker(
        meetingID: meeting.id,
        speakerID: "speaker-1",
        displayName: "Masha",
        updatedAt: Date(timeIntervalSince1970: 1_234_568_200)
    )

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    let speaker = try #require(reloaded.storedTranscript?.speakers.first)
    #expect(speaker.displayName == "Masha")
    #expect(speaker.labelSource == .userAssigned)
    #expect(speaker.matchedKnownSpeakerID == nil)
    #expect(speaker.centroid == [0.1, 0.2, 0.3])
}
```

- [ ] **Step 2: Run the focused meeting-store tests to verify the new assertion fails**

Run:

```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-known-speakers -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests
```

Expected: FAIL because `TranscriptSpeaker` and `PersistedTranscriptSpeaker` do not yet support `labelSource`, `matchedKnownSpeakerID`, or `centroid`.

- [ ] **Step 3: Add the minimal transcript speaker metadata model and persistence fields**

```swift
// QuickMeeting/Models/TranscriptSpeakerLabelSource.swift
import Foundation

enum TranscriptSpeakerLabelSource: String, Codable, Equatable, Sendable {
    case generic
    case userAssigned
    case bankMatched
}
```

```swift
// QuickMeeting/Models/TranscriptSpeaker.swift
import Foundation

struct TranscriptSpeaker: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var displayName: String
    var labelSource: TranscriptSpeakerLabelSource
    var matchedKnownSpeakerID: String?
    var centroid: [Double]?

    init(
        id: String,
        displayName: String,
        labelSource: TranscriptSpeakerLabelSource = .generic,
        matchedKnownSpeakerID: String? = nil,
        centroid: [Double]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.labelSource = labelSource
        self.matchedKnownSpeakerID = matchedKnownSpeakerID
        self.centroid = centroid
    }
}
```

```swift
// QuickMeeting/Models/PersistedTranscriptSpeaker.swift
import Foundation
import SwiftData

@Model
final class PersistedTranscriptSpeaker {
    var id: String
    var displayName: String
    var labelSourceRawValue: String
    var matchedKnownSpeakerID: String?
    var centroid: [Double]?

    init(
        id: String,
        displayName: String,
        labelSource: TranscriptSpeakerLabelSource,
        matchedKnownSpeakerID: String?,
        centroid: [Double]?
    ) {
        self.id = id
        self.displayName = displayName
        labelSourceRawValue = labelSource.rawValue
        self.matchedKnownSpeakerID = matchedKnownSpeakerID
        self.centroid = centroid
    }

    convenience init(_ speaker: TranscriptSpeaker) {
        self.init(
            id: speaker.id,
            displayName: speaker.displayName,
            labelSource: speaker.labelSource,
            matchedKnownSpeakerID: speaker.matchedKnownSpeakerID,
            centroid: speaker.centroid
        )
    }

    var value: TranscriptSpeaker {
        TranscriptSpeaker(
            id: id,
            displayName: displayName,
            labelSource: TranscriptSpeakerLabelSource(rawValue: labelSourceRawValue) ?? .generic,
            matchedKnownSpeakerID: matchedKnownSpeakerID,
            centroid: centroid
        )
    }
}
```

```swift
// QuickMeeting/Services/MeetingStore.swift
@discardableResult
func renameSpeaker(
    meetingID: UUID,
    speakerID: String,
    displayName: String,
    updatedAt: Date
) throws -> StoredTranscript {
    let meeting = try fetchMeeting(id: meetingID)
    guard meeting.storedTranscript != nil else {
        throw MeetingTranscriptStoreError.sidecarMissing
    }

    guard let speaker = meeting.transcriptSpeakers.first(where: { $0.id == speakerID }) else {
        throw MeetingTranscriptStoreError.speakerNotFound
    }

    speaker.displayName = displayName
    speaker.labelSourceRawValue = TranscriptSpeakerLabelSource.userAssigned.rawValue
    if speaker.matchedKnownSpeakerID != nil {
        speaker.matchedKnownSpeakerID = nil
    }
    meeting.setStatus(try meeting.status, updatedAt: updatedAt)
    try modelContext.save()
    return try #require(meeting.storedTranscript)
}
```

- [ ] **Step 4: Run the focused persistence tests to verify they pass**

Run:

```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-known-speakers -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests
```

Expected: PASS with the new provenance and centroid assertions green.

- [ ] **Step 5: Commit the transcript-speaker metadata slice**

```bash
rtk git add QuickMeeting/Models/TranscriptSpeakerLabelSource.swift QuickMeeting/Models/TranscriptSpeaker.swift QuickMeeting/Models/PersistedTranscriptSpeaker.swift QuickMeeting/Models/Meeting.swift QuickMeeting/Services/MeetingStore.swift QuickMeetingTests/MeetingStoreTests.swift QuickMeetingTests/MeetingTranscriptStoreTests.swift
rtk git commit -m "feat: persist transcript speaker recognition metadata"
```

## Task 2: Add the SwiftData known-speaker store with pruning

**Files:**
- Create: `QuickMeeting/Models/PersistedKnownSpeaker.swift`
- Create: `QuickMeeting/Models/PersistedKnownSpeakerCentroid.swift`
- Create: `QuickMeeting/Services/Transcription/KnownSpeakerStore.swift`
- Create: `QuickMeetingTests/KnownSpeakerStoreTests.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`

- [ ] **Step 1: Write the failing known-speaker store tests**

```swift
@MainActor
struct KnownSpeakerStoreTests {
    @Test
    func findOrCreateReusesExactNameCaseInsensitively() throws {
        let harness = try KnownSpeakerStoreHarness()
        let first = try harness.store.findOrCreateSpeaker(named: "Alice Johnson", now: .now)
        let second = try harness.store.findOrCreateSpeaker(named: "  alice johnson  ", now: .now)

        #expect(first.id == second.id)
        #expect(try harness.fetchKnownSpeakers().count == 1)
    }

    @Test
    func appendCentroidPrunesOldestWhenCapacityExceedsThree() throws {
        let harness = try KnownSpeakerStoreHarness()
        let speaker = try harness.store.findOrCreateSpeaker(named: "Alice", now: .now)

        try harness.store.appendCentroid([0.1], to: speaker.id, sourceMeetingID: nil, sourceSpeakerID: nil, now: Date(timeIntervalSince1970: 10))
        try harness.store.appendCentroid([0.2], to: speaker.id, sourceMeetingID: nil, sourceSpeakerID: nil, now: Date(timeIntervalSince1970: 20))
        try harness.store.appendCentroid([0.3], to: speaker.id, sourceMeetingID: nil, sourceSpeakerID: nil, now: Date(timeIntervalSince1970: 30))
        try harness.store.appendCentroid([0.4], to: speaker.id, sourceMeetingID: nil, sourceSpeakerID: nil, now: Date(timeIntervalSince1970: 40))

        let reloaded = try harness.fetchKnownSpeakers().first
        #expect(reloaded?.centroids.map(\.values) == [[0.2], [0.3], [0.4]])
    }
}
```

- [ ] **Step 2: Run the focused known-speaker store tests to verify they fail**

Run:

```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-known-speakers -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/KnownSpeakerStoreTests
```

Expected: FAIL because the known-speaker models and store do not exist yet.

- [ ] **Step 3: Create the known-speaker SwiftData models and store**

```swift
// QuickMeeting/Models/PersistedKnownSpeaker.swift
import Foundation
import SwiftData

@Model
final class PersistedKnownSpeaker {
    @Attribute(.unique) var id: String
    var displayName: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var centroids: [PersistedKnownSpeakerCentroid]

    init(
        id: String = UUID().uuidString,
        displayName: String,
        createdAt: Date,
        updatedAt: Date,
        centroids: [PersistedKnownSpeakerCentroid] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.centroids = centroids
    }
}
```

```swift
// QuickMeeting/Models/PersistedKnownSpeakerCentroid.swift
import Foundation
import SwiftData

@Model
final class PersistedKnownSpeakerCentroid {
    var values: [Double]
    var sourceMeetingID: UUID?
    var sourceSpeakerID: String?
    var createdAt: Date

    init(
        values: [Double],
        sourceMeetingID: UUID?,
        sourceSpeakerID: String?,
        createdAt: Date
    ) {
        self.values = values
        self.sourceMeetingID = sourceMeetingID
        self.sourceSpeakerID = sourceSpeakerID
        self.createdAt = createdAt
    }
}
```

```swift
// QuickMeeting/Services/Transcription/KnownSpeakerStore.swift
import Foundation
import SwiftData

@MainActor
struct KnownSpeakerStore {
    let modelContext: ModelContext

    func allSpeakers() throws -> [PersistedKnownSpeaker] {
        try modelContext.fetch(FetchDescriptor<PersistedKnownSpeaker>())
    }

    func findSpeaker(exactName displayName: String) throws -> PersistedKnownSpeaker? {
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !normalized.isEmpty else {
            return nil
        }

        return try allSpeakers().first {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == normalized
        }
    }

    @discardableResult
    func findOrCreateSpeaker(named displayName: String, now: Date) throws -> PersistedKnownSpeaker {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = try findSpeaker(exactName: trimmed) {
            return existing
        }

        let speaker = PersistedKnownSpeaker(displayName: trimmed, createdAt: now, updatedAt: now)
        modelContext.insert(speaker)
        try modelContext.save()
        return speaker
    }

    func speaker(id: String) throws -> PersistedKnownSpeaker? {
        let descriptor = FetchDescriptor<PersistedKnownSpeaker>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func appendCentroid(
        _ values: [Double],
        to speakerID: String,
        sourceMeetingID: UUID?,
        sourceSpeakerID: String?,
        now: Date
    ) throws {
        guard let speaker = try speaker(id: speakerID) else {
            return
        }

        speaker.centroids.append(
            PersistedKnownSpeakerCentroid(
                values: values,
                sourceMeetingID: sourceMeetingID,
                sourceSpeakerID: sourceSpeakerID,
                createdAt: now
            )
        )
        speaker.centroids.sort { $0.createdAt < $1.createdAt }
        while speaker.centroids.count > 3 {
            let removed = speaker.centroids.removeFirst()
            modelContext.delete(removed)
        }
        speaker.updatedAt = now
        try modelContext.save()
    }
}
```

```swift
// QuickMeeting/QuickMeetingApp.swift
let schema = Schema([
    Meeting.self,
    PersistedTranscriptSpeaker.self,
    PersistedTranscriptSegment.self,
    PersistedKnownSpeaker.self,
    PersistedKnownSpeakerCentroid.self,
])
```

- [ ] **Step 4: Run the focused known-speaker store tests to verify they pass**

Run:

```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-known-speakers -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/KnownSpeakerStoreTests
```

Expected: PASS with exact-name reuse and oldest-centroid pruning verified.

- [ ] **Step 5: Commit the known-speaker store slice**

```bash
rtk git add QuickMeeting/Models/PersistedKnownSpeaker.swift QuickMeeting/Models/PersistedKnownSpeakerCentroid.swift QuickMeeting/Services/Transcription/KnownSpeakerStore.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/KnownSpeakerStoreTests.swift
rtk git commit -m "feat: add known speaker persistence store"
```

## Task 3: Export known speakers to sidecar JSON and pass the launch argument

**Files:**
- Create: `QuickMeeting/Services/Transcription/KnownSpeakerJSONWriter.swift`
- Create: `QuickMeetingTests/KnownSpeakerJSONWriterTests.swift`
- Modify: `QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift`
- Modify: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing sidecar and JSON-writer tests**

```swift
@Test
func writeKnownSpeakersFileUsesSidecarShape() throws {
    let writer = KnownSpeakerJSONWriter(fileManager: .default)
    let outputURL = try writer.write(
        speakers: [
            KnownSpeakerExport(id: "known-1", centroids: [[0.1, 0.2], [0.3, 0.4]])
        ],
        directoryURL: FileManager.default.temporaryDirectory
    )

    let data = try Data(contentsOf: outputURL)
    let payload = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    let first = try #require(payload?.first)
    #expect(first["id"] as? String == "known-1")
    #expect((first["centroids"] as? [[Double]])?.count == 2)
}

@Test
func transcribePassesKnownSpeakersFileWhenStoreHasCentroids() async throws {
    let harness = try SidecarTranscriptionHarness()
    let meeting = try harness.createRecordedMeeting()
    try harness.knownSpeakerStore.findOrCreateSpeaker(named: "Alice", now: .now)
    try harness.knownSpeakerStore.appendCentroid([0.1, 0.2], to: harness.firstKnownSpeakerID(), sourceMeetingID: nil, sourceSpeakerID: nil, now: .now)
    await harness.launcher.setResult(.success([#"{"status":"completed","speakers":[],"segments":[]}"#]))

    try await harness.service.transcribe(meetingID: meeting.id)

    let request = try await #require(harness.launcher.requests.first)
    #expect(request.arguments.contains("--known-speakers-file"))
}
```

- [ ] **Step 2: Run the focused sidecar export tests to verify they fail**

Run:

```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-known-speakers -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/KnownSpeakerJSONWriterTests -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: FAIL because no JSON writer exists and the sidecar service does not yet accept a known-speaker dependency.

- [ ] **Step 3: Add JSON export support and sidecar argument wiring**

```swift
// QuickMeeting/Services/Transcription/KnownSpeakerJSONWriter.swift
import Foundation

struct KnownSpeakerExport: Codable, Equatable, Sendable {
    let id: String
    let centroids: [[Double]]
}

struct KnownSpeakerJSONWriter {
    let fileManager: FileManager
    let encoder: JSONEncoder

    init(fileManager: FileManager = .default, encoder: JSONEncoder = JSONEncoder()) {
        self.fileManager = fileManager
        self.encoder = encoder
    }

    func write(speakers: [KnownSpeakerExport], directoryURL: URL) throws -> URL {
        let outputURL = directoryURL.appendingPathComponent("known-speakers-\(UUID().uuidString).json")
        let data = try encoder.encode(speakers)
        fileManager.createFile(atPath: outputURL.path, contents: data)
        return outputURL
    }
}
```

```swift
// QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift
private let knownSpeakerStore: KnownSpeakerStore?
private let knownSpeakerJSONWriter: KnownSpeakerJSONWriter

init(
    meetingStore: MeetingStore,
    progressCenter: TranscriptionProgressCenter,
    launcher: any SidecarProcessLaunching,
    eventDecoder: SidecarTranscriptionEventDecoder? = nil,
    executableURLProvider: @escaping @Sendable () -> URL?,
    hfTokenProvider: @escaping @Sendable () -> String,
    transcriptionLanguageProvider: @escaping @Sendable () -> TranscriptionLanguage = { .none },
    initialPromptProvider: @escaping @Sendable () -> String = { "" },
    hfHomeURLProvider: @escaping @Sendable () -> URL,
    knownSpeakerStore: KnownSpeakerStore? = nil,
    knownSpeakerJSONWriter: KnownSpeakerJSONWriter = KnownSpeakerJSONWriter(),
    audioPreparer: (any SidecarTranscriptionAudioPreparing)? = nil,
    fileManager: FileManager = .default,
    dateProvider: @escaping () -> Date = Date.init
) {
    self.knownSpeakerStore = knownSpeakerStore
    self.knownSpeakerJSONWriter = knownSpeakerJSONWriter
    // keep existing assignments
}

let knownSpeakerFileURL = try makeKnownSpeakersFileIfNeeded()
defer {
    if let knownSpeakerFileURL {
        try? fileManager.removeItem(at: knownSpeakerFileURL)
    }
}

if let knownSpeakerFileURL {
    arguments.append(contentsOf: ["--known-speakers-file", knownSpeakerFileURL.path])
}
```

```swift
private func makeKnownSpeakersFileIfNeeded() throws -> URL? {
    guard let knownSpeakerStore else {
        return nil
    }

    let exports = try knownSpeakerStore.allSpeakers()
        .map { speaker in
            KnownSpeakerExport(
                id: speaker.id,
                centroids: speaker.centroids.sorted { $0.createdAt < $1.createdAt }.map(\.values)
            )
        }
        .filter { !$0.centroids.isEmpty }

    guard !exports.isEmpty else {
        return nil
    }

    return try knownSpeakerJSONWriter.write(
        speakers: exports,
        directoryURL: fileManager.temporaryDirectory
    )
}
```

- [ ] **Step 4: Run the focused export and sidecar tests to verify they pass**

Run:

```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-known-speakers -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/KnownSpeakerJSONWriterTests -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: PASS with the sidecar request containing `--known-speakers-file` only when export data exists.

- [ ] **Step 5: Commit the sidecar export slice**

```bash
rtk git add QuickMeeting/Services/Transcription/KnownSpeakerJSONWriter.swift QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift QuickMeetingTests/KnownSpeakerJSONWriterTests.swift QuickMeetingTests/SidecarTranscriptionServiceTests.swift
rtk git commit -m "feat: export known speakers for sidecar recognition"
```

## Task 4: Map sidecar speaker matches into enriched transcripts

**Files:**
- Create: `QuickMeeting/Services/Transcription/SpeakerRecognitionMapper.swift`
- Create: `QuickMeetingTests/SpeakerRecognitionMapperTests.swift`
- Modify: `QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift`
- Modify: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing mapper and sidecar transcript tests**

```swift
@Test
func mapperAppliesBankMatchedNameWhenProbabilityExceedsThreshold() {
    let mapper = SpeakerRecognitionMapper()
    let speakers = mapper.makeTranscriptSpeakers(
        sidecarSpeakers: [
            SidecarCompletedSpeaker(
                id: "SPEAKER_00",
                matchedID: "known-alice",
                probability: 0.91,
                centroid: [0.1, 0.2]
            )
        ],
        segments: [
            SidecarCompletedSegment(speaker: "SPEAKER_00", start: 0, end: 1, text: "Hello")
        ],
        knownSpeakerNamesByID: ["known-alice": "Alice"]
    )

    #expect(speakers == [
        TranscriptSpeaker(
            id: "SPEAKER_00",
            displayName: "Alice",
            labelSource: .bankMatched,
            matchedKnownSpeakerID: "known-alice",
            centroid: [0.1, 0.2]
        )
    ])
}
```

```swift
@Test
func transcribePersistsBankMatchedSpeakerMetadata() async throws {
    let harness = try SidecarTranscriptionHarness()
    let meeting = try harness.createRecordedMeeting()
    try harness.insertKnownSpeaker(id: "known-alice", displayName: "Alice", centroids: [[0.9, 0.8]])
    await harness.launcher.setResult(.success([
        #"{"status":"completed","speakers":[{"id":"SPEAKER_00","matched_id":"known-alice","probability":0.91,"centroid":[0.1,0.2]}],"segments":[{"speaker":"SPEAKER_00","start":0.0,"end":1.5,"text":"Hello"}]}"#
    ]))

    try await harness.service.transcribe(meetingID: meeting.id)

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    let speaker = try #require(reloaded.storedTranscript?.speakers.first)
    #expect(speaker.displayName == "Alice")
    #expect(speaker.labelSource == .bankMatched)
    #expect(speaker.matchedKnownSpeakerID == "known-alice")
    #expect(speaker.centroid == [0.1, 0.2])
}
```

- [ ] **Step 2: Run the focused recognition-mapping tests to verify they fail**

Run:

```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-known-speakers -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SpeakerRecognitionMapperTests -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: FAIL because the sidecar service still labels speakers purely by ordered segment appearance.

- [ ] **Step 3: Add recognition mapping and transcript construction from sidecar speaker payloads**

```swift
// QuickMeeting/Services/Transcription/SpeakerRecognitionMapper.swift
import Foundation

struct SpeakerRecognitionMapper {
    private let probabilityThreshold = 0.8

    func makeTranscriptSpeakers(
        sidecarSpeakers: [SidecarCompletedSpeaker],
        segments: [SidecarCompletedSegment],
        knownSpeakerNamesByID: [String: String]
    ) -> [TranscriptSpeaker] {
        if !sidecarSpeakers.isEmpty {
            return sidecarSpeakers.enumerated().map { index, speaker in
                guard
                    let matchedID = speaker.matchedID,
                    let probability = speaker.probability,
                    probability > probabilityThreshold,
                    let matchedName = knownSpeakerNamesByID[matchedID]
                else {
                    return TranscriptSpeaker(
                        id: speaker.id,
                        displayName: "Speaker \(index + 1)",
                        labelSource: .generic,
                        matchedKnownSpeakerID: nil,
                        centroid: speaker.centroid
                    )
                }

                return TranscriptSpeaker(
                    id: speaker.id,
                    displayName: matchedName,
                    labelSource: .bankMatched,
                    matchedKnownSpeakerID: matchedID,
                    centroid: speaker.centroid
                )
            }
        }

        let orderedSpeakerIDs = segments.reduce(into: [String]()) { result, segment in
            if !result.contains(segment.speaker) {
                result.append(segment.speaker)
            }
        }

        return orderedSpeakerIDs.enumerated().map { index, speakerID in
            TranscriptSpeaker(id: speakerID, displayName: "Speaker \(index + 1)")
        }
    }
}
```

```swift
// QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift
private let recognitionMapper: SpeakerRecognitionMapper

private func makeStoredTranscript(from payload: SidecarCompletedPayload) throws -> StoredTranscript {
    let knownSpeakerNamesByID = try Dictionary(
        uniqueKeysWithValues: (knownSpeakerStore?.allSpeakers() ?? []).map { ($0.id, $0.displayName) }
    )
    let speakers = recognitionMapper.makeTranscriptSpeakers(
        sidecarSpeakers: payload.speakers,
        segments: payload.segments,
        knownSpeakerNamesByID: knownSpeakerNamesByID
    )
    let segments = payload.segments.map {
        TranscriptSegment(text: $0.text, startTime: $0.start, endTime: $0.end, speakerID: $0.speaker)
    }
    return StoredTranscript(speakers: speakers, segments: segments)
}
```

- [ ] **Step 4: Run the focused recognition tests to verify they pass**

Run:

```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-known-speakers -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SpeakerRecognitionMapperTests -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: PASS with auto-matched speakers stored as `bankMatched` and low-confidence results still generic.

- [ ] **Step 5: Commit the recognition mapping slice**

```bash
rtk git add QuickMeeting/Services/Transcription/SpeakerRecognitionMapper.swift QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift QuickMeetingTests/SpeakerRecognitionMapperTests.swift QuickMeetingTests/SidecarTranscriptionServiceTests.swift
rtk git commit -m "feat: map sidecar speaker matches into transcripts"
```

## Task 5: Enroll centroids after accepted matches and manual renames

**Files:**
- Create: `QuickMeeting/Services/Transcription/KnownSpeakerEnrollmentService.swift`
- Create: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`

- [ ] **Step 1: Write the failing app-view-model rename tests**

```swift
@MainActor
struct AppViewModelTests {
    @Test
    func renameSpeakerPersistsMeetingRenameEvenWhenEnrollmentFails() async throws {
        let harness = try AppViewModelHarness(enrollmentResult: .failure(TestError.failed))
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [
                    TranscriptSpeaker(
                        id: "speaker-1",
                        displayName: "Speaker 1",
                        labelSource: .generic,
                        matchedKnownSpeakerID: nil,
                        centroid: [0.1, 0.2]
                    )
                ],
                segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
            )
        )

        try await harness.viewModel.renameSpeaker(
            meetingID: meeting.id,
            speakerID: "speaker-1",
            displayName: "Masha"
        )

        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.storedTranscript?.speakers.first?.displayName == "Masha")
        #expect(harness.viewModel.renameSpeakerErrorMessage == nil)
        #expect(await harness.enrollmentService.calls.count == 1)
    }
}
```

- [ ] **Step 2: Run the focused rename-enrollment tests to verify they fail**

Run:

```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-known-speakers -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: FAIL because no enrollment service exists and `AppViewModel` stops after local rename persistence.

- [ ] **Step 3: Add best-effort enrollment service and hook it into rename flow**

```swift
// QuickMeeting/Services/Transcription/KnownSpeakerEnrollmentService.swift
import Foundation

protocol KnownSpeakerEnrolling: Sendable {
    func enroll(displayName: String, speaker: TranscriptSpeaker, meetingID: UUID) async throws
}

@MainActor
final class KnownSpeakerEnrollmentService: KnownSpeakerEnrolling {
    private let store: KnownSpeakerStore
    private let dateProvider: () -> Date

    init(store: KnownSpeakerStore, dateProvider: @escaping () -> Date = Date.init) {
        self.store = store
        self.dateProvider = dateProvider
    }

    func enroll(displayName: String, speaker: TranscriptSpeaker, meetingID: UUID) async throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let centroid = speaker.centroid else {
            return
        }

        let knownSpeaker = try store.findOrCreateSpeaker(named: trimmed, now: dateProvider())
        try store.appendCentroid(
            centroid,
            to: knownSpeaker.id,
            sourceMeetingID: meetingID,
            sourceSpeakerID: speaker.id,
            now: dateProvider()
        )
    }
}
```

```swift
// QuickMeeting/ViewModels/AppViewModel.swift
private let knownSpeakerEnrollmentService: (any KnownSpeakerEnrolling)?

init(
    meetingStore: MeetingStore,
    meetingFileStore: MeetingFileStore,
    recordingService: any RecordingService,
    transcriptionService: (any TranscriptionServicing)? = nil,
    transcriptionProgressCenter: TranscriptionProgressCenter? = nil,
    recordingPermissions: (any RecordingPermissions)? = nil,
    meetingTranscriptStore: (any MeetingTranscriptStoring)? = nil,
    knownSpeakerEnrollmentService: (any KnownSpeakerEnrolling)? = nil,
    calendarIntegration: (any CalendarIntegration)? = nil,
    dateProvider: @escaping () -> Date = Date.init,
    meetingIDProvider: @escaping () -> UUID = UUID.init,
    meetingTitleFormatter: DateFormatter = AppViewModel.makeMeetingTitleFormatter()
) {
    self.knownSpeakerEnrollmentService = knownSpeakerEnrollmentService
    // keep existing assignments
}

func renameSpeaker(
    meetingID: UUID,
    speakerID: String,
    displayName: String
) async throws {
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

    do {
        let transcript = try meetingTranscriptStore.renameSpeaker(
            id: speakerID,
            to: trimmedName,
            in: meetingID
        )
        renameSpeakerErrorMessage = nil

        if let speaker = transcript.speakers.first(where: { $0.id == speakerID }) {
            do {
                try await knownSpeakerEnrollmentService?.enroll(
                    displayName: trimmedName,
                    speaker: speaker,
                    meetingID: meetingID
                )
            } catch {
                // Best-effort enrollment. Keep the successful rename.
            }
        }
    } catch {
        renameSpeakerErrorMessage = error.localizedDescription
        throw error
    }
}
```

```swift
// QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift
private let knownSpeakerEnrollmentService: (any KnownSpeakerEnrolling)?

for speaker in transcript.speakers where speaker.labelSource == .bankMatched {
    do {
        try await knownSpeakerEnrollmentService?.enroll(
            displayName: speaker.displayName,
            speaker: speaker,
            meetingID: meetingID
        )
    } catch {
        // Keep the successful transcript even if centroid enrollment fails.
    }
}
```

- [ ] **Step 4: Run the focused rename-enrollment tests to verify they pass**

Run:

```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-known-speakers -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: PASS with rename persistence remaining successful even when enrollment throws, and accepted auto-matches appending centroids best-effort.

- [ ] **Step 5: Commit the enrollment slice**

```bash
rtk git add QuickMeeting/Services/Transcription/KnownSpeakerEnrollmentService.swift QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/AppViewModelTests.swift QuickMeetingTests/SidecarTranscriptionServiceTests.swift
rtk git commit -m "feat: enroll known speakers from renames and matches"
```

## Task 6: Wire app dependencies and run focused regression coverage

**Files:**
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`
- Modify: `QuickMeetingTests/MeetingStoreTests.swift`
- Modify: `QuickMeetingTests/MeetingTranscriptStoreTests.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Add the final dependency wiring in `QuickMeetingApp`**

```swift
// QuickMeeting/QuickMeetingApp.swift
let knownSpeakerStore = KnownSpeakerStore(modelContext: modelContainer.mainContext)
let knownSpeakerEnrollmentService = KnownSpeakerEnrollmentService(store: knownSpeakerStore)

let transcriptionService = SidecarTranscriptionService(
    meetingStore: meetingStore,
    progressCenter: transcriptionProgressCenter,
    launcher: DefaultSidecarProcessLauncher(),
    executableURLProvider: { SidecarTranscriptionService.defaultExecutableURL() },
    hfTokenProvider: { huggingFaceTokenSettingsStore.loadToken() },
    transcriptionLanguageProvider: { transcriptionSettingsStore.load().language },
    initialPromptProvider: { transcriptionSettingsStore.load().initialPrompt },
    hfHomeURLProvider: { SidecarTranscriptionService.defaultHFHomeURL() },
    knownSpeakerStore: knownSpeakerStore,
    knownSpeakerEnrollmentService: knownSpeakerEnrollmentService
)

let appViewModel = AppViewModel(
    meetingStore: meetingStore,
    meetingFileStore: meetingFileStore,
    recordingService: recordingService,
    transcriptionService: transcriptionService,
    transcriptionProgressCenter: transcriptionProgressCenter,
    meetingTranscriptStore: meetingTranscriptStore,
    knownSpeakerEnrollmentService: knownSpeakerEnrollmentService,
    calendarIntegration: calendarIntegration
)
```

- [ ] **Step 2: Run the full focused regression set for this feature**

Run:

```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-known-speakers -quiet CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests -only-testing:QuickMeetingTests/KnownSpeakerStoreTests -only-testing:QuickMeetingTests/KnownSpeakerJSONWriterTests -only-testing:QuickMeetingTests/SpeakerRecognitionMapperTests -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS with transcript persistence, known-speaker export, recognition mapping, and rename enrollment all green.

- [ ] **Step 3: Commit the final wiring and regression updates**

```bash
rtk git add QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/MeetingStoreTests.swift QuickMeetingTests/MeetingTranscriptStoreTests.swift QuickMeetingTests/KnownSpeakerStoreTests.swift QuickMeetingTests/KnownSpeakerJSONWriterTests.swift QuickMeetingTests/SpeakerRecognitionMapperTests.swift QuickMeetingTests/SidecarTranscriptionServiceTests.swift QuickMeetingTests/AppViewModelTests.swift
rtk git commit -m "test: cover known speaker integration flow"
```

## Self-Review

### Spec Coverage

- Meeting-local centroid persistence is covered in Task 1 and Task 4.
- Global known-speaker SwiftData storage and 3-centroid pruning are covered in Task 2.
- Temporary JSON export and `--known-speakers-file` launch behavior are covered in Task 3.
- Auto-apply matched names only when `matched_id` exists and `probability > 0.8` is covered in Task 4.
- Best-effort centroid appends after accepted matches and manual renames are covered in Task 5.
- New app wiring in the existing SwiftData container is covered in Task 2 and Task 6.
- Future compatibility for later rename/delete UI is preserved by the separate `KnownSpeakerStore` and stable IDs introduced in Task 2.

### Placeholder Scan

- No `TODO`, `TBD`, or deferred “later” implementation steps remain in the tasks.
- Every code-changing step includes concrete code to add or update.
- Every test step includes a runnable command and an expected result.

### Type Consistency

- `TranscriptSpeaker` uses `labelSource`, `matchedKnownSpeakerID`, and `centroid` consistently across Tasks 1, 4, and 5.
- `KnownSpeakerStore` uses `findOrCreateSpeaker`, `allSpeakers`, `speaker(id:)`, and `appendCentroid` consistently across Tasks 2, 3, and 5.
- `KnownSpeakerEnrollmentService` implements `KnownSpeakerEnrolling` and is the shared dependency for both `AppViewModel` and `SidecarTranscriptionService`.
