**Goal:** Add a persistent speaker bank that learns from manual speaker renames and auto-labels future diarized speakers only when recognition is strongly confident.

**Architecture:** Keep meeting-local transcript speakers as the primary model and layer global speaker recognition on top of them. Add a SwiftData-backed speaker bank plus a focused recognition/enrollment subsystem, then insert a post-diarization recognition step into `TranscriptionService` and a best-effort enrollment hook into the existing rename flow.

**Tech Stack:** Swift, SwiftData, Foundation, Swift Testing, xcodebuild, WhisperKit, soniqo.audio

---

## File Map

### Create

- `QuickMeeting/Models/TranscriptSpeakerLabelSource.swift`
  Purpose: Define the transcript speaker provenance enum such as `generic`, `userAssigned`, and `bankMatched`.
- `QuickMeeting/Models/PersistedKnownSpeaker.swift`
  Purpose: SwiftData model for a global known speaker person.
- `QuickMeeting/Models/PersistedKnownSpeakerEmbedding.swift`
  Purpose: SwiftData model for stored embeddings plus lightweight enrollment metadata.
- `QuickMeeting/Services/Transcription/SpeakerBankStore.swift`
  Purpose: Create, fetch, update, and prune known speakers and embeddings behind one persistence boundary.
- `QuickMeeting/Services/Transcription/SpeakerAudioSegmentSelector.swift`
  Purpose: Select eligible diarized segments, crop boundary margins, and return trimmed audio spans for enrollment and recognition.
- `QuickMeeting/Services/Transcription/SpeakerEmbeddingService.swift`
  Purpose: Wrap soniqo.audio embedding generation behind a narrow protocol boundary.
- `QuickMeeting/Services/Transcription/SpeakerRecognitionService.swift`
  Purpose: Compare current meeting speakers against the bank, apply confidence and runner-up margin checks, and return matches.
- `QuickMeeting/Services/Transcription/SpeakerEnrollmentService.swift`
  Purpose: Resolve or create bank persons from renamed speakers and persist new embeddings best-effort.
- `QuickMeetingTests/SpeakerBankStoreTests.swift`
  Purpose: Verify case-insensitive exact-name reuse, new-person creation, and embedding-cap pruning.
- `QuickMeetingTests/SpeakerAudioSegmentSelectorTests.swift`
  Purpose: Verify segment filtering, adaptive boundary trimming, and too-short-core rejection.
- `QuickMeetingTests/SpeakerRecognitionServiceTests.swift`
  Purpose: Verify high-confidence recognition, low-confidence fallback, and second-best margin behavior.
- `QuickMeetingTests/SpeakerEnrollmentServiceTests.swift`
  Purpose: Verify rename-driven enrollment, bank creation/update rules, and best-effort failure handling.

### Modify

- `QuickMeeting/Models/TranscriptSpeaker.swift`
  Purpose: Add label provenance and optional matched bank person ID to meeting-local transcript speakers.
- `QuickMeeting/Models/PersistedTranscriptSpeaker.swift`
  Purpose: Persist the new transcript speaker metadata in SwiftData.
- `QuickMeeting/Models/Meeting.swift`
  Purpose: Keep transcript reconstruction aligned with the richer `TranscriptSpeaker` shape.
- `QuickMeeting/Services/MeetingStore.swift`
  Purpose: Persist user-assigned speaker metadata during rename and preserve current transcript semantics.
- `QuickMeeting/Services/Transcription/MeetingTranscriptStore.swift`
  Purpose: Keep rename persistence intact while exposing the stored transcript needed by enrollment.
- `QuickMeeting/Services/Transcription/TranscriptionService.swift`
  Purpose: Insert post-diarization recognition before meeting completion.
- `QuickMeeting/ViewModels/AppViewModel.swift`
  Purpose: Trigger best-effort speaker enrollment after a successful manual rename.
- `QuickMeeting/QuickMeetingApp.swift`
  Purpose: Register new SwiftData models and wire the speaker-bank services into app dependencies.
- `QuickMeetingTests/TranscriptionServiceTests.swift`
  Purpose: Cover recognition-assisted transcription outcomes.
- `QuickMeetingTests/AppViewModelTests.swift`
  Purpose: Cover rename success plus independent enrollment behavior.

## Task 1: Extend transcript speakers with recognition provenance

**Files:**
- Create: `QuickMeeting/Models/TranscriptSpeakerLabelSource.swift`
- Modify: `QuickMeeting/Models/TranscriptSpeaker.swift`
- Modify: `QuickMeeting/Models/PersistedTranscriptSpeaker.swift`
- Modify: `QuickMeeting/Models/Meeting.swift`
- Test: `QuickMeetingTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing transcript-speaker metadata test**

```swift
@Test
func storedTranscriptPreservesSpeakerRecognitionMetadata() {
    let transcript = StoredTranscript(
        speakers: [
            TranscriptSpeaker(
                id: "speaker-1",
                displayName: "Alice",
                labelSource: .bankMatched,
                matchedKnownSpeakerID: "known-alice"
            )
        ],
        segments: [
            TranscriptSegment(
                text: "Hello there",
                startTime: 0,
                endTime: 1,
                speakerID: "speaker-1"
            )
        ]
    )

    let meeting = Meeting(
        title: "Test",
        startedAt: .now,
        status: .completed,
        audioFilePath: "/tmp/audio.m4a",
        transcriptSpeakers: transcript.speakers.map(PersistedTranscriptSpeaker.init),
        transcriptSegments: transcript.segments.map(PersistedTranscriptSegment.init)
    )

    let restoredSpeaker = try #require(meeting.storedTranscript?.speakers.first)
    #expect(restoredSpeaker.labelSource == .bankMatched)
    #expect(restoredSpeaker.matchedKnownSpeakerID == "known-alice")
}
```

- [ ] **Step 2: Run the focused transcript metadata test to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: FAIL because `TranscriptSpeaker` and `PersistedTranscriptSpeaker` do not yet expose `labelSource` or `matchedKnownSpeakerID`.

- [ ] **Step 3: Add the minimal provenance model and persistence fields**

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

    init(
        id: String,
        displayName: String,
        labelSource: TranscriptSpeakerLabelSource = .generic,
        matchedKnownSpeakerID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.labelSource = labelSource
        self.matchedKnownSpeakerID = matchedKnownSpeakerID
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

    init(
        id: String,
        displayName: String,
        labelSource: TranscriptSpeakerLabelSource,
        matchedKnownSpeakerID: String?
    ) {
        self.id = id
        self.displayName = displayName
        labelSourceRawValue = labelSource.rawValue
        self.matchedKnownSpeakerID = matchedKnownSpeakerID
    }

    convenience init(_ speaker: TranscriptSpeaker) {
        self.init(
            id: speaker.id,
            displayName: speaker.displayName,
            labelSource: speaker.labelSource,
            matchedKnownSpeakerID: speaker.matchedKnownSpeakerID
        )
    }

    var value: TranscriptSpeaker {
        TranscriptSpeaker(
            id: id,
            displayName: displayName,
            labelSource: TranscriptSpeakerLabelSource(rawValue: labelSourceRawValue) ?? .generic,
            matchedKnownSpeakerID: matchedKnownSpeakerID
        )
    }
}
```

```swift
// QuickMeeting/Models/Meeting.swift
func completeTranscription(
    transcript: StoredTranscript,
    transcriptPreview: String,
    updatedAt: Date = Date()
) {
    transcriptFilePath = nil
    self.transcriptPreview = transcriptPreview
    transcriptSpeakers = transcript.speakers.map(PersistedTranscriptSpeaker.init)
    transcriptSegments = transcript.segments.map(PersistedTranscriptSegment.init)
    statusRawValue = MeetingStatus.completed.rawValue
    touch(updatedAt: updatedAt)
}
```

- [ ] **Step 4: Run the focused transcript metadata test again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS for the new transcript-speaker metadata assertion.

- [ ] **Step 5: Commit the transcript metadata slice**

```bash
git add QuickMeeting/Models/TranscriptSpeakerLabelSource.swift QuickMeeting/Models/TranscriptSpeaker.swift QuickMeeting/Models/PersistedTranscriptSpeaker.swift QuickMeeting/Models/Meeting.swift QuickMeetingTests/TranscriptionServiceTests.swift
git commit -m "feat: track transcript speaker label provenance"
```

## Task 2: Add the SwiftData speaker bank store

**Files:**
- Create: `QuickMeeting/Models/PersistedKnownSpeaker.swift`
- Create: `QuickMeeting/Models/PersistedKnownSpeakerEmbedding.swift`
- Create: `QuickMeeting/Services/Transcription/SpeakerBankStore.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Test: `QuickMeetingTests/SpeakerBankStoreTests.swift`

- [ ] **Step 1: Write the failing speaker-bank store tests**

```swift
import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct SpeakerBankStoreTests {
    @Test
    func findOrCreateKnownSpeakerReusesCaseInsensitiveExactNameMatch() throws {
        let harness = try SpeakerBankStoreHarness()
        let first = try harness.store.findOrCreateKnownSpeaker(named: "Alice Johnson", now: .now)
        let second = try harness.store.findOrCreateKnownSpeaker(named: "alice johnson", now: .now)

        #expect(first.persistentModelID == second.persistentModelID)
        #expect(try harness.fetchKnownSpeakers().count == 1)
    }

    @Test
    func appendEmbeddingPrunesOldestSampleWhenCapIsExceeded() throws {
        let harness = try SpeakerBankStoreHarness()
        let speaker = try harness.store.findOrCreateKnownSpeaker(named: "Alice", now: .now)

        try harness.store.appendEmbedding(
            to: speaker,
            embedding: Data([0x01]),
            sourceMeetingID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            sourceSpeakerID: "speaker-1",
            sampledDuration: 8,
            now: .now,
            maxEmbeddingsPerSpeaker: 2
        )
        try harness.store.appendEmbedding(
            to: speaker,
            embedding: Data([0x02]),
            sourceMeetingID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            sourceSpeakerID: "speaker-1",
            sampledDuration: 8,
            now: .now,
            maxEmbeddingsPerSpeaker: 2
        )
        try harness.store.appendEmbedding(
            to: speaker,
            embedding: Data([0x03]),
            sourceMeetingID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            sourceSpeakerID: "speaker-1",
            sampledDuration: 8,
            now: .now,
            maxEmbeddingsPerSpeaker: 2
        )

        let snapshot = try harness.reloadKnownSpeaker(id: speaker.id)
        #expect(snapshot.embeddings.count == 2)
        #expect(snapshot.embeddings.map(\.blob) == [Data([0x02]), Data([0x03])])
    }
}
```

- [ ] **Step 2: Run the focused speaker-bank tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SpeakerBankStoreTests
```

Expected: FAIL because the known-speaker SwiftData models and `SpeakerBankStore` do not exist yet.

- [ ] **Step 3: Add the minimal SwiftData models and bank store**

```swift
// QuickMeeting/Models/PersistedKnownSpeaker.swift
import Foundation
import SwiftData

@Model
final class PersistedKnownSpeaker {
    @Attribute(.unique) var id: String
    var displayName: String
    var normalizedDisplayName: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var embeddings: [PersistedKnownSpeakerEmbedding]

    init(
        id: String = UUID().uuidString,
        displayName: String,
        normalizedDisplayName: String,
        createdAt: Date,
        updatedAt: Date,
        embeddings: [PersistedKnownSpeakerEmbedding] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.normalizedDisplayName = normalizedDisplayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.embeddings = embeddings
    }
}
```

```swift
// QuickMeeting/Models/PersistedKnownSpeakerEmbedding.swift
import Foundation
import SwiftData

@Model
final class PersistedKnownSpeakerEmbedding {
    var blob: Data
    var sourceMeetingID: UUID
    var sourceSpeakerID: String
    var sampledDuration: TimeInterval
    var createdAt: Date

    init(
        blob: Data,
        sourceMeetingID: UUID,
        sourceSpeakerID: String,
        sampledDuration: TimeInterval,
        createdAt: Date
    ) {
        self.blob = blob
        self.sourceMeetingID = sourceMeetingID
        self.sourceSpeakerID = sourceSpeakerID
        self.sampledDuration = sampledDuration
        self.createdAt = createdAt
    }
}
```

```swift
// QuickMeeting/Services/Transcription/SpeakerBankStore.swift
import Foundation
import SwiftData

@MainActor
struct SpeakerBankStore {
    let modelContext: ModelContext

    func findOrCreateKnownSpeaker(named displayName: String, now: Date) throws -> PersistedKnownSpeaker {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let descriptor = FetchDescriptor<PersistedKnownSpeaker>(
            predicate: #Predicate { $0.normalizedDisplayName == normalizedName }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.updatedAt = now
            try modelContext.save()
            return existing
        }

        let speaker = PersistedKnownSpeaker(
            displayName: displayName,
            normalizedDisplayName: normalizedName,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(speaker)
        try modelContext.save()
        return speaker
    }

    func appendEmbedding(
        to speaker: PersistedKnownSpeaker,
        embedding: Data,
        sourceMeetingID: UUID,
        sourceSpeakerID: String,
        sampledDuration: TimeInterval,
        now: Date,
        maxEmbeddingsPerSpeaker: Int
    ) throws {
        speaker.embeddings.append(
            PersistedKnownSpeakerEmbedding(
                blob: embedding,
                sourceMeetingID: sourceMeetingID,
                sourceSpeakerID: sourceSpeakerID,
                sampledDuration: sampledDuration,
                createdAt: now
            )
        )
        speaker.embeddings.sort { $0.createdAt < $1.createdAt }
        if speaker.embeddings.count > maxEmbeddingsPerSpeaker {
            speaker.embeddings.removeFirst(speaker.embeddings.count - maxEmbeddingsPerSpeaker)
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
    PersistedKnownSpeakerEmbedding.self,
])
```

- [ ] **Step 4: Run the focused speaker-bank tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SpeakerBankStoreTests
```

Expected: PASS for case-insensitive exact-name reuse and cap pruning.

- [ ] **Step 5: Commit the speaker-bank persistence slice**

```bash
git add QuickMeeting/Models/PersistedKnownSpeaker.swift QuickMeeting/Models/PersistedKnownSpeakerEmbedding.swift QuickMeeting/Services/Transcription/SpeakerBankStore.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/SpeakerBankStoreTests.swift
git commit -m "feat: add speaker bank persistence"
```

## Task 3: Add segment selection with boundary safety margins

**Files:**
- Create: `QuickMeeting/Services/Transcription/SpeakerAudioSegmentSelector.swift`
- Test: `QuickMeetingTests/SpeakerAudioSegmentSelectorTests.swift`

- [ ] **Step 1: Write the failing segment-selector tests**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct SpeakerAudioSegmentSelectorTests {
    @Test
    func selectEligibleSpansTrimsBothSegmentBoundaries() {
        let selector = SpeakerAudioSegmentSelector(
            minimumSegmentDuration: 5,
            boundaryTrimDuration: 1,
            minimumTrimmedDuration: 3
        )

        let spans = selector.selectEligibleSpans(
            from: [
                TranscriptSegment(
                    text: "Hello there",
                    startTime: 10,
                    endTime: 20,
                    speakerID: "speaker-1"
                )
            ],
            speakerID: "speaker-1"
        )

        #expect(spans == [SpeakerAudioSpan(startTime: 11, endTime: 19)])
    }

    @Test
    func selectEligibleSpansSkipsSegmentsWhoseTrimmedCoreIsTooShort() {
        let selector = SpeakerAudioSegmentSelector(
            minimumSegmentDuration: 5,
            boundaryTrimDuration: 2,
            minimumTrimmedDuration: 3
        )

        let spans = selector.selectEligibleSpans(
            from: [
                TranscriptSegment(
                    text: "Short",
                    startTime: 0,
                    endTime: 5,
                    speakerID: "speaker-1"
                )
            ],
            speakerID: "speaker-1"
        )

        #expect(spans.isEmpty)
    }
}
```

- [ ] **Step 2: Run the focused selector tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SpeakerAudioSegmentSelectorTests
```

Expected: FAIL because `SpeakerAudioSegmentSelector` and `SpeakerAudioSpan` do not exist yet.

- [ ] **Step 3: Add the minimal selector implementation**

```swift
// QuickMeeting/Services/Transcription/SpeakerAudioSegmentSelector.swift
import Foundation

struct SpeakerAudioSpan: Equatable {
    let startTime: TimeInterval
    let endTime: TimeInterval

    var duration: TimeInterval {
        endTime - startTime
    }
}

struct SpeakerAudioSegmentSelector {
    let minimumSegmentDuration: TimeInterval
    let boundaryTrimDuration: TimeInterval
    let minimumTrimmedDuration: TimeInterval

    init(
        minimumSegmentDuration: TimeInterval = 5,
        boundaryTrimDuration: TimeInterval = 1,
        minimumTrimmedDuration: TimeInterval = 3
    ) {
        self.minimumSegmentDuration = minimumSegmentDuration
        self.boundaryTrimDuration = boundaryTrimDuration
        self.minimumTrimmedDuration = minimumTrimmedDuration
    }

    func selectEligibleSpans(
        from segments: [TranscriptSegment],
        speakerID: String
    ) -> [SpeakerAudioSpan] {
        segments.compactMap { segment in
            guard
                segment.speakerID == speakerID,
                let startTime = segment.startTime,
                let endTime = segment.endTime
            else {
                return nil
            }

            let rawDuration = endTime - startTime
            guard rawDuration >= minimumSegmentDuration else {
                return nil
            }

            let trimAmount = min(boundaryTrimDuration, max(0, (rawDuration - minimumTrimmedDuration) / 2))
            let trimmed = SpeakerAudioSpan(
                startTime: startTime + trimAmount,
                endTime: endTime - trimAmount
            )

            return trimmed.duration >= minimumTrimmedDuration ? trimmed : nil
        }
    }
}
```

- [ ] **Step 4: Run the focused selector tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SpeakerAudioSegmentSelectorTests
```

Expected: PASS for both the boundary trim and too-short-core cases.

- [ ] **Step 5: Commit the selector slice**

```bash
git add QuickMeeting/Services/Transcription/SpeakerAudioSegmentSelector.swift QuickMeetingTests/SpeakerAudioSegmentSelectorTests.swift
git commit -m "feat: add speaker audio segment selection"
```

## Task 4: Add recognition matching behind a soniqo.audio boundary

**Files:**
- Create: `QuickMeeting/Services/Transcription/SpeakerEmbeddingService.swift`
- Create: `QuickMeeting/Services/Transcription/SpeakerRecognitionService.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Test: `QuickMeetingTests/SpeakerRecognitionServiceTests.swift`

- [ ] **Step 1: Write the failing recognition tests**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct SpeakerRecognitionServiceTests {
    @Test
    func recognizeSpeakersReturnsBankMatchOnlyWhenThresholdAndMarginPass() async throws {
        let embeddingService = StubSpeakerEmbeddingService(
            currentSpeakerEmbeddings: ["speaker-1": [Data([0x01])]],
            scores: [
                SpeakerScore(candidateID: "known-alice", score: 0.92),
                SpeakerScore(candidateID: "known-bob", score: 0.61),
            ]
        )
        let service = SpeakerRecognitionService(
            embeddingService: embeddingService,
            threshold: 0.85,
            minimumMargin: 0.15
        )

        let result = try await service.matchSpeaker(
            speakerID: "speaker-1",
            spans: [SpeakerAudioSpan(startTime: 1, endTime: 9)],
            candidates: [
                KnownSpeakerCandidate(id: "known-alice", displayName: "Alice", embeddings: [Data([0x11])]),
                KnownSpeakerCandidate(id: "known-bob", displayName: "Bob", embeddings: [Data([0x22])]),
            ]
        )

        #expect(result == SpeakerRecognitionMatch(knownSpeakerID: "known-alice", displayName: "Alice"))
    }

    @Test
    func recognizeSpeakersReturnsNilWhenRunnerUpIsTooClose() async throws {
        let embeddingService = StubSpeakerEmbeddingService(
            currentSpeakerEmbeddings: ["speaker-1": [Data([0x01])]],
            scores: [
                SpeakerScore(candidateID: "known-alice", score: 0.90),
                SpeakerScore(candidateID: "known-bob", score: 0.83),
            ]
        )
        let service = SpeakerRecognitionService(
            embeddingService: embeddingService,
            threshold: 0.85,
            minimumMargin: 0.10
        )

        let result = try await service.matchSpeaker(
            speakerID: "speaker-1",
            spans: [SpeakerAudioSpan(startTime: 1, endTime: 9)],
            candidates: [
                KnownSpeakerCandidate(id: "known-alice", displayName: "Alice", embeddings: [Data([0x11])]),
                KnownSpeakerCandidate(id: "known-bob", displayName: "Bob", embeddings: [Data([0x22])]),
            ]
        )

        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run the focused recognition tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SpeakerRecognitionServiceTests
```

Expected: FAIL because the embedding boundary and recognition service do not exist yet.

- [ ] **Step 3: Add the minimal embedding protocol and recognition logic**

```swift
// QuickMeeting/Services/Transcription/SpeakerEmbeddingService.swift
import Foundation

protocol SpeakerEmbeddingService: Sendable {
    func makeEmbeddings(audioFileURL: URL, spans: [SpeakerAudioSpan]) async throws -> [Data]
    func score(
        probeEmbeddings: [Data],
        against candidateEmbeddings: [Data]
    ) async throws -> Double
}

struct KnownSpeakerCandidate: Equatable {
    let id: String
    let displayName: String
    let embeddings: [Data]
}

struct SpeakerScore: Equatable {
    let candidateID: String
    let score: Double
}
```

```swift
// QuickMeeting/Services/Transcription/SpeakerRecognitionService.swift
import Foundation

struct SpeakerRecognitionMatch: Equatable {
    let knownSpeakerID: String
    let displayName: String
}

struct SpeakerRecognitionService {
    let embeddingService: any SpeakerEmbeddingService
    let threshold: Double
    let minimumMargin: Double

    init(
        embeddingService: any SpeakerEmbeddingService,
        threshold: Double = 0.85,
        minimumMargin: Double = 0.12
    ) {
        self.embeddingService = embeddingService
        self.threshold = threshold
        self.minimumMargin = minimumMargin
    }

    func matchSpeaker(
        speakerID: String,
        spans: [SpeakerAudioSpan],
        candidates: [KnownSpeakerCandidate],
        audioFileURL: URL = URL(fileURLWithPath: "/dev/null")
    ) async throws -> SpeakerRecognitionMatch? {
        guard !spans.isEmpty else {
            return nil
        }

        let probeEmbeddings = try await embeddingService.makeEmbeddings(
            audioFileURL: audioFileURL,
            spans: spans
        )
        guard !probeEmbeddings.isEmpty else {
            return nil
        }

        let scored = try await candidates.asyncMap { candidate in
            (
                candidate,
                try await embeddingService.score(
                    probeEmbeddings: probeEmbeddings,
                    against: candidate.embeddings
                )
            )
        }
        .sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 >= threshold else {
            return nil
        }

        if let runnerUp = scored.dropFirst().first, (best.1 - runnerUp.1) < minimumMargin {
            return nil
        }

        return SpeakerRecognitionMatch(
            knownSpeakerID: best.0.id,
            displayName: best.0.displayName
        )
    }
}
```

```swift
// QuickMeeting/QuickMeetingApp.swift
let speakerEmbeddingService = SoniqoSpeakerEmbeddingService()
let speakerRecognitionService = SpeakerRecognitionService(
    embeddingService: speakerEmbeddingService
)
```

- [ ] **Step 4: Run the focused recognition tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SpeakerRecognitionServiceTests
```

Expected: PASS for the threshold and runner-up margin behavior.

- [ ] **Step 5: Commit the recognition slice**

```bash
git add QuickMeeting/Services/Transcription/SpeakerEmbeddingService.swift QuickMeeting/Services/Transcription/SpeakerRecognitionService.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/SpeakerRecognitionServiceTests.swift
git commit -m "feat: add speaker recognition service"
```

## Task 5: Insert recognition into the transcription pipeline

**Files:**
- Modify: `QuickMeeting/Services/Transcription/TranscriptionService.swift`
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing transcription recognition tests**

```swift
@Test
func transcribeAppliesKnownSpeakerNameWhenRecognitionIsStrong() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createRecordedMeeting()
    await harness.installDefaultModel(.small)
    await harness.backend.setResult(.success(
        TranscriptionResult(
            fullText: "Hello",
            segments: [TranscriptSegment(text: "Hello", startTime: 0, endTime: 12)]
        )
    ))
    await harness.diarizer.setResult(.success(
        StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", startTime: 0, endTime: 12, speakerID: "speaker-1")]
        )
    ))
    await harness.recognitionService.setMatches([
        "speaker-1": SpeakerRecognitionMatch(
            knownSpeakerID: "known-alice",
            displayName: "Alice"
        )
    ])

    try await harness.service.transcribe(meetingID: meeting.id)

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(reloaded.transcriptSpeakers.map(\.displayName) == ["Alice"])
    #expect(reloaded.transcriptSpeakers.map(\.labelSource) == [.bankMatched])
    #expect(reloaded.transcriptSpeakers.map(\.matchedKnownSpeakerID) == ["known-alice"])
}

@Test
func transcribePreservesGenericSpeakerNameWhenRecognitionReturnsNil() async throws {
    let harness = try TranscriptionServiceHarness()
    let meeting = try harness.createRecordedMeeting()
    await harness.installDefaultModel(.small)
    await harness.backend.setResult(.success(
        TranscriptionResult(
            fullText: "Hello",
            segments: [TranscriptSegment(text: "Hello", startTime: 0, endTime: 12)]
        )
    ))
    await harness.diarizer.setResult(.success(
        StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", startTime: 0, endTime: 12, speakerID: "speaker-1")]
        )
    ))

    try await harness.service.transcribe(meetingID: meeting.id)

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    #expect(reloaded.transcriptSpeakers.map(\.displayName) == ["Speaker 1"])
    #expect(reloaded.transcriptSpeakers.map(\.labelSource) == [.generic])
    #expect(reloaded.transcriptSpeakers.map(\.matchedKnownSpeakerID) == [nil])
}
```

- [ ] **Step 2: Run the focused transcription tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: FAIL because `TranscriptionService` does not yet invoke recognition or rewrite transcript speaker metadata.

- [ ] **Step 3: Add the minimal post-diarization recognition hook**

```swift
// QuickMeeting/Services/Transcription/TranscriptionService.swift
@MainActor
final class TranscriptionService: TranscriptionServicing {
    private let recognitionService: SpeakerRecognitionService?
    private let segmentSelector: SpeakerAudioSegmentSelector

    init(
        meetingStore: MeetingStore,
        modelStore: any WhisperModelStore,
        modelSettingsStore: ModelSettingsStore,
        backend: any WhisperTranscriptionBackend,
        diarizer: (any TranscriptDiarizing)? = nil,
        recognitionService: SpeakerRecognitionService? = nil,
        segmentSelector: SpeakerAudioSegmentSelector = SpeakerAudioSegmentSelector(),
        progressCenter: TranscriptionProgressCenter,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.recognitionService = recognitionService
        self.segmentSelector = segmentSelector
        ...
    }

    private func applyRecognitionIfAvailable(
        to transcript: StoredTranscript,
        audioFileURL: URL
    ) async throws -> StoredTranscript {
        guard let recognitionService else {
            return transcript
        }

        var resolved = transcript
        for index in resolved.speakers.indices {
            let speaker = resolved.speakers[index]
            let spans = segmentSelector.selectEligibleSpans(
                from: resolved.segments,
                speakerID: speaker.id
            )
            guard
                let match = try await recognitionService.matchSpeaker(
                    speakerID: speaker.id,
                    spans: spans,
                    candidates: []
                )
            else {
                continue
            }

            resolved.speakers[index].displayName = match.displayName
            resolved.speakers[index].labelSource = .bankMatched
            resolved.speakers[index].matchedKnownSpeakerID = match.knownSpeakerID
        }

        return resolved
    }
}
```

- [ ] **Step 4: Run the focused transcription tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS for both the strong-match rename and the nil-match fallback.

- [ ] **Step 5: Commit the transcription integration slice**

```bash
git add QuickMeeting/Services/Transcription/TranscriptionService.swift QuickMeetingTests/TranscriptionServiceTests.swift
git commit -m "feat: apply speaker bank matches during transcription"
```

## Task 6: Trigger best-effort enrollment after manual rename

**Files:**
- Create: `QuickMeeting/Services/Transcription/SpeakerEnrollmentService.swift`
- Modify: `QuickMeeting/Services/MeetingStore.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Test: `QuickMeetingTests/SpeakerEnrollmentServiceTests.swift`

- [ ] **Step 1: Write the failing enrollment tests**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct SpeakerEnrollmentServiceTests {
    @Test
    func enrollRenamedSpeakerCreatesKnownSpeakerAndEmbeddings() async throws {
        let bankStore = SpeakerBankStoreSpy()
        let embeddingService = StubSpeakerEmbeddingService(
            currentSpeakerEmbeddings: ["speaker-1": [Data([0x01]), Data([0x02])]],
            scores: []
        )
        let selector = SpeakerAudioSegmentSelector(
            minimumSegmentDuration: 5,
            boundaryTrimDuration: 1,
            minimumTrimmedDuration: 3
        )
        let service = SpeakerEnrollmentService(
            bankStore: bankStore,
            embeddingService: embeddingService,
            segmentSelector: selector,
            maxEmbeddingsPerSpeaker: 5,
            dateProvider: { .now }
        )
        let transcript = StoredTranscript(
            speakers: [
                TranscriptSpeaker(
                    id: "speaker-1",
                    displayName: "Alice",
                    labelSource: .userAssigned
                )
            ],
            segments: [
                TranscriptSegment(text: "Hello there", startTime: 0, endTime: 12, speakerID: "speaker-1")
            ]
        )

        try await service.enrollRenamedSpeaker(
            meetingID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            audioFileURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
            transcript: transcript,
            speakerID: "speaker-1",
            displayName: "Alice"
        )

        #expect(bankStore.createdOrReusedNames == ["Alice"])
        #expect(bankStore.appendedEmbeddings.count == 2)
    }
}
```

- [ ] **Step 2: Run the focused enrollment tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SpeakerEnrollmentServiceTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: FAIL because `SpeakerEnrollmentService` does not exist and `AppViewModel.renameSpeaker(...)` does not invoke it.

- [ ] **Step 3: Add the minimal enrollment service and rename hook**

```swift
// QuickMeeting/Services/Transcription/SpeakerEnrollmentService.swift
import Foundation

protocol SpeakerEnrolling: Sendable {
    func enrollRenamedSpeaker(
        meetingID: UUID,
        audioFileURL: URL,
        transcript: StoredTranscript,
        speakerID: String,
        displayName: String
    ) async throws
}

struct SpeakerEnrollmentService: SpeakerEnrolling {
    let bankStore: SpeakerBankStore
    let embeddingService: any SpeakerEmbeddingService
    let segmentSelector: SpeakerAudioSegmentSelector
    let maxEmbeddingsPerSpeaker: Int
    let dateProvider: () -> Date

    func enrollRenamedSpeaker(
        meetingID: UUID,
        audioFileURL: URL,
        transcript: StoredTranscript,
        speakerID: String,
        displayName: String
    ) async throws {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            return
        }

        let spans = segmentSelector.selectEligibleSpans(from: transcript.segments, speakerID: speakerID)
        guard !spans.isEmpty else {
            return
        }

        let embeddings = try await embeddingService.makeEmbeddings(
            audioFileURL: audioFileURL,
            spans: spans
        )
        guard !embeddings.isEmpty else {
            return
        }

        let speaker = try bankStore.findOrCreateKnownSpeaker(named: normalizedName, now: dateProvider())
        for embedding in embeddings {
            try bankStore.appendEmbedding(
                to: speaker,
                embedding: embedding,
                sourceMeetingID: meetingID,
                sourceSpeakerID: speakerID,
                sampledDuration: spans.reduce(0) { $0 + $1.duration },
                now: dateProvider(),
                maxEmbeddingsPerSpeaker: maxEmbeddingsPerSpeaker
            )
        }
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
    guard let speaker = meeting.transcriptSpeakers.first(where: { $0.id == speakerID }) else {
        throw MeetingTranscriptStoreError.speakerNotFound
    }

    speaker.displayName = displayName
    speaker.labelSourceRawValue = TranscriptSpeakerLabelSource.userAssigned.rawValue
    speaker.matchedKnownSpeakerID = nil
    meeting.setStatus(try meeting.status, updatedAt: updatedAt)
    try modelContext.save()
    return try #require(meeting.storedTranscript)
}
```

```swift
// QuickMeeting/ViewModels/AppViewModel.swift
private let speakerEnrollmentService: (any SpeakerEnrolling)?

init(
    meetingStore: MeetingStore,
    meetingFileStore: MeetingFileStore,
    recordingService: any RecordingService,
    transcriptionService: (any TranscriptionServicing)? = nil,
    transcriptionProgressCenter: TranscriptionProgressCenter? = nil,
    recordingPermissions: (any RecordingPermissions)? = nil,
    meetingTranscriptStore: (any MeetingTranscriptStoring)? = nil,
    speakerEnrollmentService: (any SpeakerEnrolling)? = nil,
    calendarIntegration: (any CalendarIntegration)? = nil,
    dateProvider: @escaping () -> Date = Date.init,
    meetingIDProvider: @escaping () -> UUID = UUID.init,
    meetingTitleFormatter: DateFormatter = AppViewModel.makeMeetingTitleFormatter()
) {
    self.speakerEnrollmentService = speakerEnrollmentService
    ...
}

func renameSpeaker(
    meetingID: UUID,
    speakerID: String,
    displayName: String
) async throws {
    do {
        let transcript = try meetingTranscriptStore.renameSpeaker(
            id: speakerID,
            to: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            in: meetingID
        )
        renameSpeakerErrorMessage = nil

        if let speakerEnrollmentService {
            let meeting = try meetingStore.fetchMeeting(id: meetingID)
            Task {
                try? await speakerEnrollmentService.enrollRenamedSpeaker(
                    meetingID: meetingID,
                    audioFileURL: URL(fileURLWithPath: meeting.audioFilePath),
                    transcript: transcript,
                    speakerID: speakerID,
                    displayName: displayName
                )
            }
        }
    } catch {
        renameSpeakerErrorMessage = error.localizedDescription
        throw error
    }
}
```

- [ ] **Step 4: Run the focused enrollment tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SpeakerEnrollmentServiceTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS for rename-driven enrollment and for rename succeeding even if later enrollment work fails.

- [ ] **Step 5: Commit the enrollment slice**

```bash
git add QuickMeeting/Services/Transcription/SpeakerEnrollmentService.swift QuickMeeting/Services/MeetingStore.swift QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/SpeakerEnrollmentServiceTests.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: enroll renamed speakers into speaker bank"
```

## Task 7: Verify the end-to-end slices together

**Files:**
- Modify: `QuickMeetingTests/TranscriptionServiceTests.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeetingTests/SpeakerRecognitionServiceTests.swift`
- Modify: `QuickMeetingTests/SpeakerEnrollmentServiceTests.swift`

- [ ] **Step 1: Add a final focused regression test for user rename overriding automatic labeling**

```swift
@Test
func manualRenameClearsPriorBankMatchMetadata() async throws {
    let harness = try AppViewModelTestHarness()
    let meeting = try harness.createCompletedMeeting(
        transcript: StoredTranscript(
            speakers: [
                TranscriptSpeaker(
                    id: "speaker-1",
                    displayName: "Alice",
                    labelSource: .bankMatched,
                    matchedKnownSpeakerID: "known-alice"
                )
            ],
            segments: [TranscriptSegment(text: "Hello", startTime: 0, endTime: 12, speakerID: "speaker-1")]
        ),
        preview: "Hello"
    )

    try await harness.viewModel.renameSpeaker(
        meetingID: meeting.id,
        speakerID: "speaker-1",
        displayName: "Alicia"
    )

    let reloaded = try harness.reloadMeeting(id: meeting.id)
    let speaker = try #require(reloaded.storedTranscript?.speakers.first)
    #expect(speaker.displayName == "Alicia")
    #expect(speaker.labelSource == .userAssigned)
    #expect(speaker.matchedKnownSpeakerID == nil)
}
```

- [ ] **Step 2: Run the focused combined suites**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-speaker-bank "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/TranscriptionServiceTests -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/SpeakerBankStoreTests -only-testing:QuickMeetingTests/SpeakerAudioSegmentSelectorTests -only-testing:QuickMeetingTests/SpeakerRecognitionServiceTests -only-testing:QuickMeetingTests/SpeakerEnrollmentServiceTests
```

Expected: PASS across all focused speaker-bank suites.

- [ ] **Step 3: Commit the verification slice**

```bash
git add QuickMeetingTests/TranscriptionServiceTests.swift QuickMeetingTests/AppViewModelTests.swift QuickMeetingTests/SpeakerRecognitionServiceTests.swift QuickMeetingTests/SpeakerEnrollmentServiceTests.swift
git commit -m "test: verify speaker bank recognition flow"
```
