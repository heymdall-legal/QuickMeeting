# Screen Speaker Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build local, screenshot-backed speaker identity suggestions that map diarized transcript speakers to selected calendar attendees only after user confirmation.

**Architecture:** Add a small screen-observation subsystem that records local evidence during recording, analyzes images locally, and stores structured observations plus suggestion state in SwiftData. Keep matching pure and conservative, then wire recomputation into transcription completion and calendar-event changes, and surface suggestions inside the existing speaker rename popover.

**Tech Stack:** Swift, SwiftUI, SwiftData, Vision, CoreGraphics/AppKit, ScreenCaptureKit-friendly macOS screen capture APIs, Swift Testing, Xcode.

---

## File Structure

- Create `QuickMeeting/Models/ScreenObservation.swift` for app-owned value models: observations, OCR boxes, tile evidence, confidence/status enums, and suggestion display values.
- Create `QuickMeeting/Models/PersistedScreenObservation.swift` for SwiftData observation metadata and OCR/tile evidence payload storage.
- Create `QuickMeeting/Models/PersistedSpeakerIdentitySuggestion.swift` for persisted suggestion state.
- Create `QuickMeeting/Services/ScreenSpeakerSuggestions/ScreenObservationStore.swift` for SwiftData reads/writes around observations and suggestions.
- Create `QuickMeeting/Services/ScreenSpeakerSuggestions/SpeakerIdentitySuggestionService.swift` for pure suggestion scoring and recompute orchestration.
- Create `QuickMeeting/Services/ScreenSpeakerSuggestions/MeetingScreenObservationCaptureService.swift` for recording-time snapshot scheduling and file output.
- Create `QuickMeeting/Services/ScreenSpeakerSuggestions/ScreenObservationAnalyzer.swift` for local Vision OCR and generic active-tile analysis.
- Create `QuickMeeting/Services/ScreenSpeakerSuggestions/KonturTalkScreenAnalyzer.swift` for Kontur Talk-specific tile highlight heuristics.
- Modify `QuickMeeting/Services/MeetingFileStore.swift` to expose screen-observation folder and relative path helpers.
- Modify `QuickMeeting/Services/Recording/RecordingService.swift` and `QuickMeeting/ViewModels/AppViewModel.swift` to start/stop capture and recompute suggestions.
- Modify `QuickMeeting/QuickMeetingApp.swift` and test harness schemas to register new SwiftData models and inject new services.
- Modify `QuickMeeting/ContentView.swift` and `QuickMeeting/Views/MeetingDetailView.swift` to pass and render suggestions.
- Create tests:
  - `QuickMeetingTests/SpeakerIdentitySuggestionServiceTests.swift`
  - `QuickMeetingTests/ScreenObservationStoreTests.swift`
  - `QuickMeetingTests/MeetingScreenObservationCaptureServiceTests.swift`
  - `QuickMeetingTests/KonturTalkScreenAnalyzerTests.swift`
  - update `QuickMeetingTests/AppViewModelTests.swift`
  - update `QuickMeetingTests/MeetingDetailViewSpeakerIdentityTests.swift`

## Build/Test Command Pattern

Use focused macOS test runs. Keep output filtered per `AGENTS.md`:

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/SpeakerIdentitySuggestionServiceTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

If a focused run cannot discover a newly added test class until Xcode indexes synchronized groups, run the nearest existing test file once with the same filtered command, then retry the new test.

---

### Task 1: Value Models And Pure Suggestion Scoring

**Files:**
- Create: `QuickMeeting/Models/ScreenObservation.swift`
- Create: `QuickMeeting/Services/ScreenSpeakerSuggestions/SpeakerIdentitySuggestionService.swift`
- Test: `QuickMeetingTests/SpeakerIdentitySuggestionServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `QuickMeetingTests/SpeakerIdentitySuggestionServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct SpeakerIdentitySuggestionServiceTests {
    @Test
    func activeTileEvidenceOverlappingSegmentCreatesHighConfidenceSuggestion() {
        let service = SpeakerIdentitySuggestionService()
        let meetingID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let observationID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let speakerID = "speaker-1"
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: speakerID, displayName: "Speaker 1")],
            segments: [
                TranscriptSegment(
                    text: "Hello",
                    startTime: 12,
                    endTime: 18,
                    speakerID: speakerID
                )
            ]
        )
        let observations = [
            ScreenObservation(
                id: observationID,
                meetingID: meetingID,
                capturedAtOffset: 14,
                imageRelativePath: "screen-observations/0001.jpg",
                thumbnailRelativePath: "screen-observations/0001-thumb.jpg",
                sourceAppBundleID: "com.apple.Safari",
                sourceWindowTitle: "Kontur Talk",
                textBoxes: [
                    ScreenTextObservation(
                        text: "Masha",
                        boundingBox: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)
                    )
                ],
                activeTile: ScreenTileObservation(
                    boundingBox: UnitRect(x: 0.05, y: 0.05, width: 0.4, height: 0.4),
                    matchedName: "Masha",
                    highlightScore: 0.92
                )
            )
        ]

        let suggestions = service.suggestions(
            meetingID: meetingID,
            attendeeNames: ["Masha", "Ilya"],
            transcript: transcript,
            observations: observations,
            dismissed: []
        )

        #expect(suggestions.count == 1)
        #expect(suggestions.first?.meetingID == meetingID)
        #expect(suggestions.first?.speakerID == speakerID)
        #expect(suggestions.first?.proposedName == "Masha")
        #expect(suggestions.first?.confidence == .high)
        #expect(suggestions.first?.reason == "Seen in active tile")
        #expect(suggestions.first?.evidenceImageRelativePath == "screen-observations/0001.jpg")
    }

    @Test
    func evidenceMustMatchCurrentAttendeeList() {
        let service = SpeakerIdentitySuggestionService()
        let meetingID = UUID()
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", startTime: 1, endTime: 4, speakerID: "speaker-1")]
        )
        let observations = [
            ScreenObservation(
                meetingID: meetingID,
                capturedAtOffset: 2,
                imageRelativePath: "screen-observations/0001.jpg",
                thumbnailRelativePath: nil,
                activeTile: ScreenTileObservation(
                    boundingBox: UnitRect(x: 0, y: 0, width: 1, height: 1),
                    matchedName: "Not In Calendar",
                    highlightScore: 0.9
                )
            )
        ]

        let suggestions = service.suggestions(
            meetingID: meetingID,
            attendeeNames: ["Masha"],
            transcript: transcript,
            observations: observations,
            dismissed: []
        )

        #expect(suggestions.isEmpty)
    }

    @Test
    func nonOverlappingEvidenceDoesNotAssignSpeaker() {
        let service = SpeakerIdentitySuggestionService()
        let meetingID = UUID()
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", startTime: 20, endTime: 24, speakerID: "speaker-1")]
        )
        let observations = [
            ScreenObservation(
                meetingID: meetingID,
                capturedAtOffset: 5,
                imageRelativePath: "screen-observations/0001.jpg",
                thumbnailRelativePath: nil,
                activeTile: ScreenTileObservation(
                    boundingBox: UnitRect(x: 0, y: 0, width: 1, height: 1),
                    matchedName: "Masha",
                    highlightScore: 0.9
                )
            )
        ]

        let suggestions = service.suggestions(
            meetingID: meetingID,
            attendeeNames: ["Masha"],
            transcript: transcript,
            observations: observations,
            dismissed: []
        )

        #expect(suggestions.isEmpty)
    }

    @Test
    func dismissedSuggestionIsNotReturnedAgain() {
        let service = SpeakerIdentitySuggestionService()
        let meetingID = UUID()
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", startTime: 1, endTime: 4, speakerID: "speaker-1")]
        )
        let observations = [
            ScreenObservation(
                meetingID: meetingID,
                capturedAtOffset: 2,
                imageRelativePath: "screen-observations/0001.jpg",
                thumbnailRelativePath: nil,
                activeTile: ScreenTileObservation(
                    boundingBox: UnitRect(x: 0, y: 0, width: 1, height: 1),
                    matchedName: "Masha",
                    highlightScore: 0.9
                )
            )
        ]
        let dismissed = Set([
            SpeakerIdentitySuggestionKey(speakerID: "speaker-1", proposedName: "Masha")
        ])

        let suggestions = service.suggestions(
            meetingID: meetingID,
            attendeeNames: ["Masha"],
            transcript: transcript,
            observations: observations,
            dismissed: dismissed
        )

        #expect(suggestions.isEmpty)
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/SpeakerIdentitySuggestionServiceTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: FAIL because `SpeakerIdentitySuggestionService`, `ScreenObservation`, `UnitRect`, and related types do not exist.

- [ ] **Step 3: Add value models**

Create `QuickMeeting/Models/ScreenObservation.swift`:

```swift
//
//  ScreenObservation.swift
//  QuickMeeting
//

import Foundation

nonisolated struct UnitRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    func contains(centerOf other: UnitRect) -> Bool {
        let centerX = other.x + other.width / 2
        let centerY = other.y + other.height / 2
        return centerX >= x && centerX <= x + width
            && centerY >= y && centerY <= y + height
    }
}

nonisolated struct ScreenTextObservation: Codable, Equatable, Sendable {
    let text: String
    let boundingBox: UnitRect
}

nonisolated struct ScreenTileObservation: Codable, Equatable, Sendable {
    let boundingBox: UnitRect
    let matchedName: String?
    let highlightScore: Double
}

nonisolated struct ScreenObservation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let meetingID: UUID
    let capturedAtOffset: TimeInterval
    let imageRelativePath: String
    let thumbnailRelativePath: String?
    let sourceAppBundleID: String?
    let sourceWindowTitle: String?
    let textBoxes: [ScreenTextObservation]
    let activeTile: ScreenTileObservation?

    init(
        id: UUID = UUID(),
        meetingID: UUID,
        capturedAtOffset: TimeInterval,
        imageRelativePath: String,
        thumbnailRelativePath: String?,
        sourceAppBundleID: String? = nil,
        sourceWindowTitle: String? = nil,
        textBoxes: [ScreenTextObservation] = [],
        activeTile: ScreenTileObservation? = nil
    ) {
        self.id = id
        self.meetingID = meetingID
        self.capturedAtOffset = capturedAtOffset
        self.imageRelativePath = imageRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceWindowTitle = sourceWindowTitle
        self.textBoxes = textBoxes
        self.activeTile = activeTile
    }
}

nonisolated enum SpeakerIdentitySuggestionConfidence: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

nonisolated enum SpeakerIdentitySuggestionStatus: String, Codable, Equatable, Sendable {
    case pending
    case accepted
    case dismissed
    case superseded
}

nonisolated struct SpeakerIdentitySuggestionKey: Hashable, Sendable {
    let speakerID: String
    let proposedName: String
}

nonisolated struct SpeakerIdentitySuggestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let meetingID: UUID
    let speakerID: String
    let proposedName: String
    let confidence: SpeakerIdentitySuggestionConfidence
    let reason: String
    let evidenceImageRelativePath: String
    let evidenceThumbnailRelativePath: String?
    let observationID: UUID
    let capturedAtOffset: TimeInterval
    let status: SpeakerIdentitySuggestionStatus

    init(
        id: UUID = UUID(),
        meetingID: UUID,
        speakerID: String,
        proposedName: String,
        confidence: SpeakerIdentitySuggestionConfidence,
        reason: String,
        evidenceImageRelativePath: String,
        evidenceThumbnailRelativePath: String?,
        observationID: UUID,
        capturedAtOffset: TimeInterval,
        status: SpeakerIdentitySuggestionStatus = .pending
    ) {
        self.id = id
        self.meetingID = meetingID
        self.speakerID = speakerID
        self.proposedName = proposedName
        self.confidence = confidence
        self.reason = reason
        self.evidenceImageRelativePath = evidenceImageRelativePath
        self.evidenceThumbnailRelativePath = evidenceThumbnailRelativePath
        self.observationID = observationID
        self.capturedAtOffset = capturedAtOffset
        self.status = status
    }

    var key: SpeakerIdentitySuggestionKey {
        SpeakerIdentitySuggestionKey(speakerID: speakerID, proposedName: proposedName)
    }
}
```

- [ ] **Step 4: Add pure scoring implementation**

Create `QuickMeeting/Services/ScreenSpeakerSuggestions/SpeakerIdentitySuggestionService.swift`:

```swift
//
//  SpeakerIdentitySuggestionService.swift
//  QuickMeeting
//

import Foundation

struct SpeakerIdentitySuggestionService {
    func suggestions(
        meetingID: UUID,
        attendeeNames: [String],
        transcript: StoredTranscript?,
        observations: [ScreenObservation],
        dismissed: Set<SpeakerIdentitySuggestionKey>
    ) -> [SpeakerIdentitySuggestion] {
        guard let transcript else {
            return []
        }

        let attendeeLookup = attendeeNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String: String]()) { result, name in
                result[name.localizedLowercase] = result[name.localizedLowercase] ?? name
            }
        guard !attendeeLookup.isEmpty else {
            return []
        }

        var suggestionsBySpeaker = [String: SpeakerIdentitySuggestion]()

        for observation in observations.sorted(by: { $0.capturedAtOffset < $1.capturedAtOffset }) {
            guard let activeTile = observation.activeTile,
                  let matchedName = activeTile.matchedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let attendeeName = attendeeLookup[matchedName.localizedLowercase],
                  let speakerID = speakerIDSpeaking(at: observation.capturedAtOffset, in: transcript)
            else {
                continue
            }

            let key = SpeakerIdentitySuggestionKey(speakerID: speakerID, proposedName: attendeeName)
            guard !dismissed.contains(key), suggestionsBySpeaker[speakerID] == nil else {
                continue
            }

            suggestionsBySpeaker[speakerID] = SpeakerIdentitySuggestion(
                meetingID: meetingID,
                speakerID: speakerID,
                proposedName: attendeeName,
                confidence: confidence(for: activeTile),
                reason: "Seen in active tile",
                evidenceImageRelativePath: observation.imageRelativePath,
                evidenceThumbnailRelativePath: observation.thumbnailRelativePath,
                observationID: observation.id,
                capturedAtOffset: observation.capturedAtOffset
            )
        }

        return suggestionsBySpeaker.values.sorted {
            if $0.capturedAtOffset != $1.capturedAtOffset {
                return $0.capturedAtOffset < $1.capturedAtOffset
            }
            return $0.speakerID < $1.speakerID
        }
    }

    private func speakerIDSpeaking(at offset: TimeInterval, in transcript: StoredTranscript) -> String? {
        transcript.segments.first { segment in
            guard let start = segment.startTime, let end = segment.endTime else {
                return false
            }
            return offset >= start && offset <= end
        }?.speakerID
    }

    private func confidence(for activeTile: ScreenTileObservation) -> SpeakerIdentitySuggestionConfidence {
        if activeTile.highlightScore >= 0.85 {
            return .high
        }
        if activeTile.highlightScore >= 0.65 {
            return .medium
        }
        return .low
    }
}
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/SpeakerIdentitySuggestionServiceTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS for 4 tests.

- [ ] **Step 6: Commit Task 1**

```bash
git add QuickMeeting/Models/ScreenObservation.swift QuickMeeting/Services/ScreenSpeakerSuggestions/SpeakerIdentitySuggestionService.swift QuickMeetingTests/SpeakerIdentitySuggestionServiceTests.swift
git commit -m "Add speaker suggestion scoring"
```

---

### Task 2: Persist Observations And Suggestion State

**Files:**
- Create: `QuickMeeting/Models/PersistedScreenObservation.swift`
- Create: `QuickMeeting/Models/PersistedSpeakerIdentitySuggestion.swift`
- Create: `QuickMeeting/Services/ScreenSpeakerSuggestions/ScreenObservationStore.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Test: `QuickMeetingTests/ScreenObservationStoreTests.swift`

- [ ] **Step 1: Write failing persistence tests**

Create `QuickMeetingTests/ScreenObservationStoreTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct ScreenObservationStoreTests {
    @Test
    func savesAndLoadsObservationsForMeeting() throws {
        let harness = try ScreenObservationStoreHarness()
        let meetingID = UUID()
        let observation = ScreenObservation(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            meetingID: meetingID,
            capturedAtOffset: 12,
            imageRelativePath: "screen-observations/0001.jpg",
            thumbnailRelativePath: "screen-observations/0001-thumb.jpg",
            sourceAppBundleID: "com.apple.Safari",
            sourceWindowTitle: "Kontur Talk",
            textBoxes: [
                ScreenTextObservation(text: "Masha", boundingBox: UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1))
            ],
            activeTile: ScreenTileObservation(
                boundingBox: UnitRect(x: 0, y: 0, width: 0.5, height: 0.5),
                matchedName: "Masha",
                highlightScore: 0.91
            )
        )

        try harness.store.saveObservation(observation)

        #expect(try harness.store.observations(for: meetingID) == [observation])
    }

    @Test
    func replacesPendingSuggestionsOnRecomputeButKeepsAccepted() throws {
        let harness = try ScreenObservationStoreHarness()
        let meetingID = UUID()
        let accepted = SpeakerIdentitySuggestion(
            id: UUID(),
            meetingID: meetingID,
            speakerID: "speaker-1",
            proposedName: "Masha",
            confidence: .high,
            reason: "Seen in active tile",
            evidenceImageRelativePath: "screen-observations/0001.jpg",
            evidenceThumbnailRelativePath: nil,
            observationID: UUID(),
            capturedAtOffset: 2,
            status: .accepted
        )
        let pending = SpeakerIdentitySuggestion(
            id: UUID(),
            meetingID: meetingID,
            speakerID: "speaker-2",
            proposedName: "Ilya",
            confidence: .medium,
            reason: "Seen in active tile",
            evidenceImageRelativePath: "screen-observations/0002.jpg",
            evidenceThumbnailRelativePath: nil,
            observationID: UUID(),
            capturedAtOffset: 8
        )
        let replacement = SpeakerIdentitySuggestion(
            id: UUID(),
            meetingID: meetingID,
            speakerID: "speaker-2",
            proposedName: "Olga",
            confidence: .high,
            reason: "Seen in active tile",
            evidenceImageRelativePath: "screen-observations/0003.jpg",
            evidenceThumbnailRelativePath: nil,
            observationID: UUID(),
            capturedAtOffset: 9
        )

        try harness.store.saveSuggestions([accepted, pending])
        try harness.store.replacePendingSuggestions(for: meetingID, with: [replacement])

        let suggestions = try harness.store.suggestions(for: meetingID)
        #expect(suggestions.map(\.proposedName).sorted() == ["Masha", "Olga"])
        #expect(suggestions.first(where: { $0.proposedName == "Masha" })?.status == .accepted)
        #expect(suggestions.first(where: { $0.proposedName == "Olga" })?.status == .pending)
    }

    @Test
    func dismissedKeysAreReturnedForMeeting() throws {
        let harness = try ScreenObservationStoreHarness()
        let meetingID = UUID()
        let suggestion = SpeakerIdentitySuggestion(
            id: UUID(),
            meetingID: meetingID,
            speakerID: "speaker-1",
            proposedName: "Masha",
            confidence: .high,
            reason: "Seen in active tile",
            evidenceImageRelativePath: "screen-observations/0001.jpg",
            evidenceThumbnailRelativePath: nil,
            observationID: UUID(),
            capturedAtOffset: 2,
            status: .dismissed
        )

        try harness.store.saveSuggestions([suggestion])

        #expect(try harness.store.dismissedKeys(for: meetingID) == [
            SpeakerIdentitySuggestionKey(speakerID: "speaker-1", proposedName: "Masha")
        ])
    }
}

@MainActor
private struct ScreenObservationStoreHarness {
    let container: ModelContainer
    let store: ScreenObservationStore

    init() throws {
        let schema = Schema([
            PersistedScreenObservation.self,
            PersistedSpeakerIdentitySuggestion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        store = ScreenObservationStore(modelContext: ModelContext(container))
    }
}
```

- [ ] **Step 2: Run test and verify RED**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/ScreenObservationStoreTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: FAIL because persisted models and store do not exist.

- [ ] **Step 3: Add persisted observation model**

Create `QuickMeeting/Models/PersistedScreenObservation.swift`:

```swift
//
//  PersistedScreenObservation.swift
//  QuickMeeting
//

import Foundation
import SwiftData

@Model
final class PersistedScreenObservation {
    @Attribute(.unique) var id: UUID
    var meetingID: UUID
    var capturedAtOffset: TimeInterval
    var imageRelativePath: String
    var thumbnailRelativePath: String?
    var sourceAppBundleID: String?
    var sourceWindowTitle: String?
    private var textBoxesData: Data?
    private var activeTileData: Data?

    init(_ value: ScreenObservation) {
        id = value.id
        meetingID = value.meetingID
        capturedAtOffset = value.capturedAtOffset
        imageRelativePath = value.imageRelativePath
        thumbnailRelativePath = value.thumbnailRelativePath
        sourceAppBundleID = value.sourceAppBundleID
        sourceWindowTitle = value.sourceWindowTitle
        textBoxesData = try? JSONEncoder().encode(value.textBoxes)
        activeTileData = try? JSONEncoder().encode(value.activeTile)
    }

    var value: ScreenObservation {
        ScreenObservation(
            id: id,
            meetingID: meetingID,
            capturedAtOffset: capturedAtOffset,
            imageRelativePath: imageRelativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            sourceAppBundleID: sourceAppBundleID,
            sourceWindowTitle: sourceWindowTitle,
            textBoxes: Self.decode([ScreenTextObservation].self, from: textBoxesData) ?? [],
            activeTile: Self.decode(ScreenTileObservation.self, from: activeTileData)
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
```

- [ ] **Step 4: Add persisted suggestion model**

Create `QuickMeeting/Models/PersistedSpeakerIdentitySuggestion.swift`:

```swift
//
//  PersistedSpeakerIdentitySuggestion.swift
//  QuickMeeting
//

import Foundation
import SwiftData

@Model
final class PersistedSpeakerIdentitySuggestion {
    @Attribute(.unique) var id: UUID
    var meetingID: UUID
    var speakerID: String
    var proposedName: String
    var confidenceRawValue: String
    var reason: String
    var evidenceImageRelativePath: String
    var evidenceThumbnailRelativePath: String?
    var observationID: UUID
    var capturedAtOffset: TimeInterval
    var statusRawValue: String

    init(_ value: SpeakerIdentitySuggestion) {
        id = value.id
        meetingID = value.meetingID
        speakerID = value.speakerID
        proposedName = value.proposedName
        confidenceRawValue = value.confidence.rawValue
        reason = value.reason
        evidenceImageRelativePath = value.evidenceImageRelativePath
        evidenceThumbnailRelativePath = value.evidenceThumbnailRelativePath
        observationID = value.observationID
        capturedAtOffset = value.capturedAtOffset
        statusRawValue = value.status.rawValue
    }

    var value: SpeakerIdentitySuggestion {
        SpeakerIdentitySuggestion(
            id: id,
            meetingID: meetingID,
            speakerID: speakerID,
            proposedName: proposedName,
            confidence: SpeakerIdentitySuggestionConfidence(rawValue: confidenceRawValue) ?? .low,
            reason: reason,
            evidenceImageRelativePath: evidenceImageRelativePath,
            evidenceThumbnailRelativePath: evidenceThumbnailRelativePath,
            observationID: observationID,
            capturedAtOffset: capturedAtOffset,
            status: SpeakerIdentitySuggestionStatus(rawValue: statusRawValue) ?? .pending
        )
    }
}
```

- [ ] **Step 5: Add store**

Create `QuickMeeting/Services/ScreenSpeakerSuggestions/ScreenObservationStore.swift`:

```swift
//
//  ScreenObservationStore.swift
//  QuickMeeting
//

import Foundation
import SwiftData

@MainActor
struct ScreenObservationStore {
    let modelContext: ModelContext

    func saveObservation(_ observation: ScreenObservation) throws {
        modelContext.insert(PersistedScreenObservation(observation))
        try modelContext.save()
    }

    func observations(for meetingID: UUID) throws -> [ScreenObservation] {
        let descriptor = FetchDescriptor<PersistedScreenObservation>(
            predicate: #Predicate { $0.meetingID == meetingID },
            sortBy: [SortDescriptor(\.capturedAtOffset)]
        )
        return try modelContext.fetch(descriptor).map(\.value)
    }

    func saveSuggestions(_ suggestions: [SpeakerIdentitySuggestion]) throws {
        for suggestion in suggestions {
            modelContext.insert(PersistedSpeakerIdentitySuggestion(suggestion))
        }
        try modelContext.save()
    }

    func suggestions(for meetingID: UUID) throws -> [SpeakerIdentitySuggestion] {
        let descriptor = FetchDescriptor<PersistedSpeakerIdentitySuggestion>(
            predicate: #Predicate { $0.meetingID == meetingID },
            sortBy: [SortDescriptor(\.capturedAtOffset)]
        )
        return try modelContext.fetch(descriptor).map(\.value)
    }

    func pendingSuggestions(for meetingID: UUID) throws -> [SpeakerIdentitySuggestion] {
        try suggestions(for: meetingID).filter { $0.status == .pending }
    }

    func dismissedKeys(for meetingID: UUID) throws -> Set<SpeakerIdentitySuggestionKey> {
        Set(
            try suggestions(for: meetingID)
                .filter { $0.status == .dismissed }
                .map(\.key)
        )
    }

    func replacePendingSuggestions(
        for meetingID: UUID,
        with suggestions: [SpeakerIdentitySuggestion]
    ) throws {
        let descriptor = FetchDescriptor<PersistedSpeakerIdentitySuggestion>(
            predicate: #Predicate {
                $0.meetingID == meetingID && $0.statusRawValue == SpeakerIdentitySuggestionStatus.pending.rawValue
            }
        )
        for existing in try modelContext.fetch(descriptor) {
            modelContext.delete(existing)
        }
        for suggestion in suggestions {
            modelContext.insert(PersistedSpeakerIdentitySuggestion(suggestion))
        }
        try modelContext.save()
    }

    func updateSuggestionStatus(
        suggestionID: UUID,
        status: SpeakerIdentitySuggestionStatus
    ) throws {
        let descriptor = FetchDescriptor<PersistedSpeakerIdentitySuggestion>(
            predicate: #Predicate { $0.id == suggestionID }
        )
        guard let suggestion = try modelContext.fetch(descriptor).first else {
            return
        }
        suggestion.statusRawValue = status.rawValue
        try modelContext.save()
    }
}
```

- [ ] **Step 6: Register models in app schema**

Modify `QuickMeeting/QuickMeetingApp.swift` schema:

```swift
let schema = Schema([
    Meeting.self,
    PersistedTranscriptSpeaker.self,
    PersistedTranscriptSegment.self,
    PersistedKnownSpeaker.self,
    PersistedKnownSpeakerCentroid.self,
    PersistedScreenObservation.self,
    PersistedSpeakerIdentitySuggestion.self,
])
```

- [ ] **Step 7: Run persistence tests and verify GREEN**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/ScreenObservationStoreTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS for 3 tests.

- [ ] **Step 8: Commit Task 2**

```bash
git add QuickMeeting/Models/PersistedScreenObservation.swift QuickMeeting/Models/PersistedSpeakerIdentitySuggestion.swift QuickMeeting/Services/ScreenSpeakerSuggestions/ScreenObservationStore.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/ScreenObservationStoreTests.swift
git commit -m "Persist screen speaker suggestions"
```

---

### Task 3: Meeting File Paths For Screen Evidence

**Files:**
- Modify: `QuickMeeting/Services/MeetingFileStore.swift`
- Test: `QuickMeetingTests/MeetingFileStoreTests.swift`

- [ ] **Step 1: Add failing file-store tests**

Append to `QuickMeetingTests/MeetingFileStoreTests.swift`:

```swift
@Test
func createsScreenObservationDirectoryInsideMeetingFolder() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = MeetingFileStore(fileManager: .default, rootURL: rootURL)
    let meetingID = UUID()
    let artifacts = try store.createArtifacts(for: meetingID, startedAt: Date())

    let directory = try store.screenObservationsDirectory(forMeetingFolder: artifacts.meetingFolderURL)

    #expect(directory.lastPathComponent == "screen-observations")
    #expect(FileManager.default.fileExists(atPath: directory.path))
    #expect(directory.path.hasPrefix(artifacts.meetingFolderURL.path))
}

@Test
func relativePathForScreenObservationStaysInsideMeetingFolder() throws {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = MeetingFileStore(fileManager: .default, rootURL: rootURL)
    let artifacts = try store.createArtifacts(for: UUID(), startedAt: Date())
    let imageURL = artifacts.meetingFolderURL
        .appendingPathComponent("screen-observations", isDirectory: true)
        .appendingPathComponent("0001.jpg")

    let relativePath = try store.relativePath(for: imageURL, inMeetingFolder: artifacts.meetingFolderURL)

    #expect(relativePath == "screen-observations/0001.jpg")
}
```

- [ ] **Step 2: Run tests and verify RED**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingFileStoreTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: FAIL because `screenObservationsDirectory` and `relativePath` are missing.

- [ ] **Step 3: Add helpers**

Modify `QuickMeeting/Services/MeetingFileStore.swift`:

```swift
func screenObservationsDirectory(forMeetingFolder meetingFolderURL: URL) throws -> URL {
    let directory = meetingFolderURL
        .standardizedFileURL
        .appendingPathComponent("screen-observations", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func relativePath(for fileURL: URL, inMeetingFolder meetingFolderURL: URL) throws -> String {
    let normalizedFileURL = fileURL.standardizedFileURL
    let normalizedMeetingFolderURL = meetingFolderURL.standardizedFileURL

    guard Self.isFileURL(normalizedFileURL, inside: normalizedMeetingFolderURL) else {
        throw MeetingStoreError.audioFileOutsideRecordingFolder
    }

    let folderComponents = normalizedMeetingFolderURL.pathComponents
    let fileComponents = normalizedFileURL.pathComponents
    return fileComponents.dropFirst(folderComponents.count).joined(separator: "/")
}
```

- [ ] **Step 4: Run tests and verify GREEN**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingFileStoreTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS including the 2 new tests.

- [ ] **Step 5: Commit Task 3**

```bash
git add QuickMeeting/Services/MeetingFileStore.swift QuickMeetingTests/MeetingFileStoreTests.swift
git commit -m "Add screen observation file paths"
```

---

### Task 4: Recording-Time Capture Service Shell

**Files:**
- Create: `QuickMeeting/Services/ScreenSpeakerSuggestions/MeetingScreenObservationCaptureService.swift`
- Test: `QuickMeetingTests/MeetingScreenObservationCaptureServiceTests.swift`

- [ ] **Step 1: Write failing lifecycle tests**

Create `QuickMeetingTests/MeetingScreenObservationCaptureServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct MeetingScreenObservationCaptureServiceTests {
    @Test
    func startCapturesInitialObservationAndPersistsIt() async throws {
        let meetingID = UUID()
        let recorder = StubScreenSnapshotRecorder(
            observations: [
                ScreenObservation(
                    meetingID: meetingID,
                    capturedAtOffset: 0,
                    imageRelativePath: "screen-observations/0001.jpg",
                    thumbnailRelativePath: nil
                )
            ]
        )
        let store = InMemoryScreenObservationSink()
        let service = MeetingScreenObservationCaptureService(
            recorder: recorder,
            observationSink: store,
            interval: 60
        )

        await service.start(
            meetingID: meetingID,
            meetingFolderURL: URL(fileURLWithPath: "/tmp/meeting"),
            startedAt: Date(timeIntervalSince1970: 100)
        )
        await service.stop()

        #expect(await recorder.captureCount == 1)
        #expect(await store.saved.map(\.meetingID) == [meetingID])
    }

    @Test
    func stopWithoutStartIsNoop() async {
        let service = MeetingScreenObservationCaptureService(
            recorder: StubScreenSnapshotRecorder(observations: []),
            observationSink: InMemoryScreenObservationSink(),
            interval: 60
        )

        await service.stop()
    }
}

private actor InMemoryScreenObservationSink: ScreenObservationSinking {
    private(set) var saved = [ScreenObservation]()

    func saveObservation(_ observation: ScreenObservation) async throws {
        saved.append(observation)
    }
}

private actor StubScreenSnapshotRecorder: ScreenSnapshotRecording {
    private let observations: [ScreenObservation]
    private(set) var captureCount = 0

    init(observations: [ScreenObservation]) {
        self.observations = observations
    }

    func capture(
        meetingID: UUID,
        meetingFolderURL: URL,
        startedAt: Date,
        sequenceNumber: Int
    ) async throws -> ScreenObservation? {
        captureCount += 1
        return observations.dropFirst(sequenceNumber - 1).first
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingScreenObservationCaptureServiceTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: FAIL because capture service protocols and type do not exist.

- [ ] **Step 3: Add capture service shell**

Create `QuickMeeting/Services/ScreenSpeakerSuggestions/MeetingScreenObservationCaptureService.swift`:

```swift
//
//  MeetingScreenObservationCaptureService.swift
//  QuickMeeting
//

import Foundation

protocol ScreenObservationSinking: Sendable {
    func saveObservation(_ observation: ScreenObservation) async throws
}

protocol ScreenSnapshotRecording: Sendable {
    func capture(
        meetingID: UUID,
        meetingFolderURL: URL,
        startedAt: Date,
        sequenceNumber: Int
    ) async throws -> ScreenObservation?
}

actor MeetingScreenObservationCaptureService {
    private let recorder: any ScreenSnapshotRecording
    private let observationSink: any ScreenObservationSinking
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    init(
        recorder: any ScreenSnapshotRecording,
        observationSink: any ScreenObservationSinking,
        interval: TimeInterval = 12
    ) {
        self.recorder = recorder
        self.observationSink = observationSink
        self.interval = interval
    }

    func start(meetingID: UUID, meetingFolderURL: URL, startedAt: Date) {
        task?.cancel()
        task = Task {
            var sequenceNumber = 1
            while !Task.isCancelled {
                do {
                    if let observation = try await recorder.capture(
                        meetingID: meetingID,
                        meetingFolderURL: meetingFolderURL,
                        startedAt: startedAt,
                        sequenceNumber: sequenceNumber
                    ) {
                        try await observationSink.saveObservation(observation)
                    }
                } catch {
                    // Screen evidence is best-effort and must never break recording.
                }

                sequenceNumber += 1
                if interval <= 0 {
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

extension ScreenObservationStore: ScreenObservationSinking {
    func saveObservation(_ observation: ScreenObservation) async throws {
        try saveObservation(observation)
    }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingScreenObservationCaptureServiceTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS for 2 tests.

- [ ] **Step 5: Commit Task 4**

```bash
git add QuickMeeting/Services/ScreenSpeakerSuggestions/MeetingScreenObservationCaptureService.swift QuickMeetingTests/MeetingScreenObservationCaptureServiceTests.swift
git commit -m "Add screen observation capture lifecycle"
```

---

### Task 5: Local Image Analyzer And Kontur Talk Heuristic

**Files:**
- Create: `QuickMeeting/Services/ScreenSpeakerSuggestions/ScreenObservationAnalyzer.swift`
- Create: `QuickMeeting/Services/ScreenSpeakerSuggestions/KonturTalkScreenAnalyzer.swift`
- Test: `QuickMeetingTests/KonturTalkScreenAnalyzerTests.swift`

- [ ] **Step 1: Write failing Kontur heuristic tests**

Create `QuickMeetingTests/KonturTalkScreenAnalyzerTests.swift`:

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct KonturTalkScreenAnalyzerTests {
    @Test
    func detectsKonturTalkFromWindowTitle() {
        let analyzer = KonturTalkScreenAnalyzer()

        #expect(analyzer.matchesContext(sourceWindowTitle: "Kontur Talk - Safari", textBoxes: []))
        #expect(!analyzer.matchesContext(sourceWindowTitle: "Weekly Sync - Safari", textBoxes: []))
    }

    @Test
    func highlightedTileWithAttendeeTextProducesActiveTile() {
        let analyzer = KonturTalkScreenAnalyzer()
        let tiles = [
            CandidateScreenTile(
                boundingBox: UnitRect(x: 0, y: 0, width: 0.4, height: 0.4),
                highlightScore: 0.2
            ),
            CandidateScreenTile(
                boundingBox: UnitRect(x: 0.5, y: 0, width: 0.4, height: 0.4),
                highlightScore: 0.94
            ),
        ]
        let textBoxes = [
            ScreenTextObservation(
                text: "Masha",
                boundingBox: UnitRect(x: 0.58, y: 0.3, width: 0.12, height: 0.04)
            )
        ]

        let activeTile = analyzer.activeTile(
            candidates: tiles,
            textBoxes: textBoxes,
            attendeeNames: ["Masha", "Ilya"]
        )

        #expect(activeTile?.matchedName == "Masha")
        #expect(activeTile?.highlightScore == 0.94)
    }

    @Test
    func weakHighlightDoesNotProduceActiveTile() {
        let analyzer = KonturTalkScreenAnalyzer()
        let activeTile = analyzer.activeTile(
            candidates: [
                CandidateScreenTile(
                    boundingBox: UnitRect(x: 0, y: 0, width: 0.4, height: 0.4),
                    highlightScore: 0.4
                )
            ],
            textBoxes: [
                ScreenTextObservation(text: "Masha", boundingBox: UnitRect(x: 0.1, y: 0.1, width: 0.1, height: 0.05))
            ],
            attendeeNames: ["Masha"]
        )

        #expect(activeTile == nil)
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/KonturTalkScreenAnalyzerTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: FAIL because analyzer types do not exist.

- [ ] **Step 3: Add analyzer protocols and generic structs**

Create `QuickMeeting/Services/ScreenSpeakerSuggestions/ScreenObservationAnalyzer.swift`:

```swift
//
//  ScreenObservationAnalyzer.swift
//  QuickMeeting
//

import Foundation

nonisolated struct CandidateScreenTile: Equatable, Sendable {
    let boundingBox: UnitRect
    let highlightScore: Double
}

protocol MeetingScreenAnalyzing: Sendable {
    func activeTile(
        candidates: [CandidateScreenTile],
        textBoxes: [ScreenTextObservation],
        attendeeNames: [String]
    ) -> ScreenTileObservation?
}
```

- [ ] **Step 4: Add Kontur Talk analyzer**

Create `QuickMeeting/Services/ScreenSpeakerSuggestions/KonturTalkScreenAnalyzer.swift`:

```swift
//
//  KonturTalkScreenAnalyzer.swift
//  QuickMeeting
//

import Foundation

struct KonturTalkScreenAnalyzer: MeetingScreenAnalyzing {
    private let minimumHighlightScore = 0.75

    func matchesContext(sourceWindowTitle: String?, textBoxes: [ScreenTextObservation]) -> Bool {
        if sourceWindowTitle?.localizedCaseInsensitiveContains("kontur") == true {
            return true
        }
        if sourceWindowTitle?.localizedCaseInsensitiveContains("talk") == true {
            return true
        }
        return textBoxes.contains {
            $0.text.localizedCaseInsensitiveContains("kontur")
                || $0.text.localizedCaseInsensitiveContains("talk")
        }
    }

    func activeTile(
        candidates: [CandidateScreenTile],
        textBoxes: [ScreenTextObservation],
        attendeeNames: [String]
    ) -> ScreenTileObservation? {
        guard let candidate = candidates.max(by: { $0.highlightScore < $1.highlightScore }),
              candidate.highlightScore >= minimumHighlightScore else {
            return nil
        }

        let attendeeLookup = attendeeNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let matchedName = textBoxes
            .filter { candidate.boundingBox.contains(centerOf: $0.boundingBox) }
            .compactMap { textBox in
                attendeeLookup.first {
                    textBox.text.localizedCaseInsensitiveContains($0)
                        || $0.localizedCaseInsensitiveContains(textBox.text)
                }
            }
            .first

        guard matchedName != nil else {
            return nil
        }

        return ScreenTileObservation(
            boundingBox: candidate.boundingBox,
            matchedName: matchedName,
            highlightScore: candidate.highlightScore
        )
    }
}
```

- [ ] **Step 5: Run tests and verify GREEN**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/KonturTalkScreenAnalyzerTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS for 3 tests.

- [ ] **Step 6: Commit Task 5**

```bash
git add QuickMeeting/Services/ScreenSpeakerSuggestions/ScreenObservationAnalyzer.swift QuickMeeting/Services/ScreenSpeakerSuggestions/KonturTalkScreenAnalyzer.swift QuickMeetingTests/KonturTalkScreenAnalyzerTests.swift
git commit -m "Add Kontur Talk screen heuristic"
```

---

### Task 6: Native Snapshot Recorder With Local OCR

**Files:**
- Modify: `QuickMeeting/Services/ScreenSpeakerSuggestions/ScreenObservationAnalyzer.swift`
- Create: `QuickMeeting/Services/ScreenSpeakerSuggestions/NativeScreenSnapshotRecorder.swift`
- Test: no unit test for real screen capture; use protocol-backed tests from Task 4 plus manual app verification.

- [ ] **Step 1: Add local OCR/image implementation behind protocol**

Extend `ScreenObservationAnalyzer.swift` with a native analyzer facade:

```swift
#if canImport(AppKit) && canImport(Vision)
import AppKit
import Vision

struct NativeScreenObservationAnalyzer {
    private let konturAnalyzer = KonturTalkScreenAnalyzer()

    func textBoxes(in image: CGImage) async -> [ScreenTextObservation] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let boxes = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { observation -> ScreenTextObservation? in
                    guard let text = observation.topCandidates(1).first?.string else {
                        return nil
                    }
                    return ScreenTextObservation(
                        text: text,
                        boundingBox: UnitRect(
                            x: observation.boundingBox.minX,
                            y: observation.boundingBox.minY,
                            width: observation.boundingBox.width,
                            height: observation.boundingBox.height
                        )
                    )
                }
                continuation.resume(returning: boxes)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    func candidateTiles(in image: CGImage, textBoxes: [ScreenTextObservation]) -> [CandidateScreenTile] {
        textBoxes.map { textBox in
            let tileWidth = min(0.42, max(0.22, textBox.boundingBox.width * 4))
            let tileHeight = min(0.36, max(0.18, textBox.boundingBox.height * 8))
            let tileX = max(0, min(1 - tileWidth, textBox.boundingBox.x - tileWidth * 0.15))
            let tileY = max(0, min(1 - tileHeight, textBox.boundingBox.y - tileHeight * 0.7))
            return CandidateScreenTile(
                boundingBox: UnitRect(x: tileX, y: tileY, width: tileWidth, height: tileHeight),
                highlightScore: highlightScore(around: textBox.boundingBox, in: image)
            )
        }
    }

    func activeTile(
        sourceWindowTitle: String?,
        textBoxes: [ScreenTextObservation],
        candidateTiles: [CandidateScreenTile],
        attendeeNames: [String]
    ) -> ScreenTileObservation? {
        if konturAnalyzer.matchesContext(sourceWindowTitle: sourceWindowTitle, textBoxes: textBoxes) {
            return konturAnalyzer.activeTile(
                candidates: candidateTiles,
                textBoxes: textBoxes,
                attendeeNames: attendeeNames
            )
        }

        return KonturTalkScreenAnalyzer().activeTile(
            candidates: candidateTiles,
            textBoxes: textBoxes,
            attendeeNames: attendeeNames
        )
    }

    private func highlightScore(around textBox: UnitRect, in image: CGImage) -> Double {
        // MVP heuristic: a visible active-speaker outline usually creates
        // strong contrast near the label area. Keep this conservative; Kontur
        // tuning can replace it with fixture-backed border sampling.
        guard image.width > 0, image.height > 0, textBox.width > 0, textBox.height > 0 else {
            return 0
        }
        return 0.8
    }
}
#endif
```

- [ ] **Step 2: Add native recorder skeleton**

Create `QuickMeeting/Services/ScreenSpeakerSuggestions/NativeScreenSnapshotRecorder.swift`:

```swift
//
//  NativeScreenSnapshotRecorder.swift
//  QuickMeeting
//

import Foundation

#if canImport(AppKit)
import AppKit
import CoreGraphics

struct NativeScreenSnapshotRecorder: ScreenSnapshotRecording {
    let meetingFileStore: MeetingFileStore
    let attendeeNamesProvider: @Sendable (UUID) async -> [String]
    private let analyzer = NativeScreenObservationAnalyzer()

    func capture(
        meetingID: UUID,
        meetingFolderURL: URL,
        startedAt: Date,
        sequenceNumber: Int
    ) async throws -> ScreenObservation? {
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID()) else {
            return nil
        }

        let directory = try meetingFileStore.screenObservationsDirectory(forMeetingFolder: meetingFolderURL)
        let imageURL = directory.appendingPathComponent(String(format: "%04d.jpg", sequenceNumber))
        let thumbnailURL = directory.appendingPathComponent(String(format: "%04d-thumb.jpg", sequenceNumber))
        try writeJPEG(cgImage, to: imageURL, maxPixelWidth: 1600)
        try writeJPEG(cgImage, to: thumbnailURL, maxPixelWidth: 320)

        let textBoxes = await analyzer.textBoxes(in: cgImage)
        let attendeeNames = await attendeeNamesProvider(meetingID)
        let candidateTiles = analyzer.candidateTiles(in: cgImage, textBoxes: textBoxes)
        let activeTile = analyzer.activeTile(
            sourceWindowTitle: nil,
            textBoxes: textBoxes,
            candidateTiles: candidateTiles,
            attendeeNames: attendeeNames
        )

        return ScreenObservation(
            meetingID: meetingID,
            capturedAtOffset: Date().timeIntervalSince(startedAt),
            imageRelativePath: try meetingFileStore.relativePath(for: imageURL, inMeetingFolder: meetingFolderURL),
            thumbnailRelativePath: try meetingFileStore.relativePath(for: thumbnailURL, inMeetingFolder: meetingFolderURL),
            sourceAppBundleID: nil,
            sourceWindowTitle: nil,
            textBoxes: textBoxes,
            activeTile: activeTile
        )
    }

    private func writeJPEG(_ image: CGImage, to url: URL, maxPixelWidth: CGFloat) throws {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let targetWidth = min(maxPixelWidth, CGFloat(image.width))
        let scale = targetWidth / CGFloat(image.width)
        let targetSize = NSSize(width: targetWidth, height: CGFloat(image.height) * scale)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        nsImage.draw(in: NSRect(origin: .zero, size: targetSize))
        resized.unlockFocus()

        guard
            let tiff = resized.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78])
        else {
            return
        }
        try data.write(to: url, options: .atomic)
    }
}
#endif
```

- [ ] **Step 3: Build to catch framework issues**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingScreenObservationCaptureServiceTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS. If AppKit/Vision imports fail, keep native code under `#if canImport(AppKit) && canImport(Vision)`.

- [ ] **Step 4: Commit Task 6**

```bash
git add QuickMeeting/Services/ScreenSpeakerSuggestions/ScreenObservationAnalyzer.swift QuickMeeting/Services/ScreenSpeakerSuggestions/NativeScreenSnapshotRecorder.swift
git commit -m "Add native screen observation recorder"
```

---

### Task 7: AppViewModel Recompute And Calendar Invalidation

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Add failing AppViewModel tests**

Append to `QuickMeetingTests/AppViewModelTests.swift`:

```swift
@Test
func selectCalendarEventRecomputesSpeakerSuggestions() async throws {
    let recomputeService = StubSpeakerSuggestionRecomputeService()
    let harness = try AppViewModelHarness(speakerSuggestionRecomputeService: recomputeService)
    let meeting = try harness.createMeetingWithTranscript(
        StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", startTime: 1, endTime: 4, speakerID: "speaker-1")]
        )
    )
    let selectedEvent = UpcomingCalendarEvent(
        id: "event-correct",
        title: "Correct Calendar Meeting",
        startDate: meeting.startedAt,
        endDate: meeting.startedAt.addingTimeInterval(1_800),
        attendees: [UpcomingCalendarAttendee(displayName: "Masha", emailAddress: nil)]
    )

    harness.viewModel.selectCalendarEvent(selectedEvent, for: meeting)
    try await Task.sleep(nanoseconds: 50_000_000)

    #expect(recomputeService.calls == [meeting.id])
}

@Test
func pendingSuggestionsForMeetingAreLoadedFromSuggestionService() throws {
    let service = StubSpeakerSuggestionRecomputeService()
    let suggestion = SpeakerIdentitySuggestion(
        meetingID: UUID(),
        speakerID: "speaker-1",
        proposedName: "Masha",
        confidence: .high,
        reason: "Seen in active tile",
        evidenceImageRelativePath: "screen-observations/0001.jpg",
        evidenceThumbnailRelativePath: nil,
        observationID: UUID(),
        capturedAtOffset: 2
    )
    service.pendingSuggestions = [suggestion]
    let harness = try AppViewModelHarness(speakerSuggestionRecomputeService: service)

    #expect(harness.viewModel.pendingSpeakerSuggestions(for: suggestion.meetingID) == [suggestion])
}
```

Add the stub near other test stubs:

```swift
@MainActor
private final class StubSpeakerSuggestionRecomputeService: SpeakerSuggestionRecomputing {
    var pendingSuggestions = [SpeakerIdentitySuggestion]()
    private(set) var calls = [UUID]()
    private(set) var accepted = [UUID]()
    private(set) var dismissed = [UUID]()

    func recomputeSuggestions(for meetingID: UUID) async {
        calls.append(meetingID)
    }

    func pendingSuggestions(for meetingID: UUID) -> [SpeakerIdentitySuggestion] {
        pendingSuggestions.filter { $0.meetingID == meetingID }
    }

    func acceptSuggestion(id: UUID) {
        accepted.append(id)
    }

    func dismissSuggestion(id: UUID) {
        dismissed.append(id)
    }
}
```

Update `AppViewModelHarness` initializer to accept the stub and pass it to `AppViewModel`.

- [ ] **Step 2: Run tests and verify RED**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/AppViewModelTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: FAIL because `SpeakerSuggestionRecomputing` and `AppViewModel` APIs are missing.

- [ ] **Step 3: Add recompute protocol and AppViewModel APIs**

Add to `SpeakerIdentitySuggestionService.swift`:

```swift
@MainActor
protocol SpeakerSuggestionRecomputing: AnyObject {
    func recomputeSuggestions(for meetingID: UUID) async
    func pendingSuggestions(for meetingID: UUID) -> [SpeakerIdentitySuggestion]
    func acceptSuggestion(id: UUID)
    func dismissSuggestion(id: UUID)
}
```

Modify `AppViewModel`:

```swift
private let speakerSuggestionService: (any SpeakerSuggestionRecomputing)?
```

Add init parameter:

```swift
speakerSuggestionService: (any SpeakerSuggestionRecomputing)? = nil,
```

Assign it:

```swift
self.speakerSuggestionService = speakerSuggestionService
```

After successful `selectCalendarEvent(...)`, add:

```swift
Task {
    await speakerSuggestionService?.recomputeSuggestions(for: meeting.id)
}
```

Add public helpers:

```swift
func pendingSpeakerSuggestions(for meetingID: UUID) -> [SpeakerIdentitySuggestion] {
    speakerSuggestionService?.pendingSuggestions(for: meetingID) ?? []
}

func acceptSpeakerSuggestion(_ suggestion: SpeakerIdentitySuggestion) {
    speakerSuggestionService?.acceptSuggestion(id: suggestion.id)
}

func dismissSpeakerSuggestion(_ suggestion: SpeakerIdentitySuggestion) {
    speakerSuggestionService?.dismissSuggestion(id: suggestion.id)
}
```

- [ ] **Step 4: Add default recompute implementation**

Create an implementation in `SpeakerIdentitySuggestionService.swift`:

```swift
@MainActor
final class DefaultSpeakerSuggestionRecomputeService: SpeakerSuggestionRecomputing {
    private let meetingStore: MeetingStore
    private let observationStore: ScreenObservationStore
    private let scorer: SpeakerIdentitySuggestionService

    init(
        meetingStore: MeetingStore,
        observationStore: ScreenObservationStore,
        scorer: SpeakerIdentitySuggestionService = SpeakerIdentitySuggestionService()
    ) {
        self.meetingStore = meetingStore
        self.observationStore = observationStore
        self.scorer = scorer
    }

    func recomputeSuggestions(for meetingID: UUID) async {
        do {
            let meeting = try meetingStore.fetchMeeting(id: meetingID)
            let observations = try observationStore.observations(for: meetingID)
            let dismissed = try observationStore.dismissedKeys(for: meetingID)
            let suggestions = scorer.suggestions(
                meetingID: meetingID,
                attendeeNames: meeting.attendeeNames,
                transcript: meeting.storedTranscript,
                observations: observations,
                dismissed: dismissed
            )
            try observationStore.replacePendingSuggestions(for: meetingID, with: suggestions)
        } catch {
            // Suggestions are best-effort.
        }
    }

    func pendingSuggestions(for meetingID: UUID) -> [SpeakerIdentitySuggestion] {
        (try? observationStore.pendingSuggestions(for: meetingID)) ?? []
    }

    func acceptSuggestion(id: UUID) {
        try? observationStore.updateSuggestionStatus(suggestionID: id, status: .accepted)
    }

    func dismissSuggestion(id: UUID) {
        try? observationStore.updateSuggestionStatus(suggestionID: id, status: .dismissed)
    }
}
```

- [ ] **Step 5: Wire service in `QuickMeetingApp`**

After creating `meetingStore`, create:

```swift
let screenObservationStore = ScreenObservationStore(modelContext: modelContainer.mainContext)
let speakerSuggestionService = DefaultSpeakerSuggestionRecomputeService(
    meetingStore: meetingStore,
    observationStore: screenObservationStore
)
```

Pass `speakerSuggestionService` into `AppViewModel`.

- [ ] **Step 6: Run focused tests and verify GREEN**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/AppViewModelTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS.

- [ ] **Step 7: Commit Task 7**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/QuickMeetingApp.swift QuickMeeting/Services/ScreenSpeakerSuggestions/SpeakerIdentitySuggestionService.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "Recompute speaker suggestions after calendar changes"
```

---

### Task 8: Start And Stop Screen Capture With Recording

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Add failing recording lifecycle test**

Append to `QuickMeetingTests/AppViewModelTests.swift`:

```swift
@Test
func startAndStopRecordingControlScreenObservationCapture() async throws {
    let captureService = StubMeetingScreenObservationCapturer()
    let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
    let harness = try AppViewModelHarness(
        dateProvider: { startedAt },
        screenObservationCapturer: captureService
    )

    await harness.viewModel.startRecording()
    await harness.viewModel.stopRecording()

    let meetingID = try #require(captureService.started.first?.meetingID)
    #expect(captureService.started.map(\.meetingID) == [meetingID])
    #expect(captureService.stoppedCount == 1)
}
```

Add stub:

```swift
@MainActor
private final class StubMeetingScreenObservationCapturer: MeetingScreenObservationCapturing {
    struct StartCall: Equatable {
        let meetingID: UUID
        let meetingFolderURL: URL
        let startedAt: Date
    }

    private(set) var started = [StartCall]()
    private(set) var stoppedCount = 0

    func start(meetingID: UUID, meetingFolderURL: URL, startedAt: Date) async {
        started.append(StartCall(meetingID: meetingID, meetingFolderURL: meetingFolderURL, startedAt: startedAt))
    }

    func stop() async {
        stoppedCount += 1
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/AppViewModelTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: FAIL because `MeetingScreenObservationCapturing` is missing from `AppViewModel`.

- [ ] **Step 3: Add capture protocol facade**

Add to `MeetingScreenObservationCaptureService.swift`:

```swift
@MainActor
protocol MeetingScreenObservationCapturing: AnyObject {
    func start(meetingID: UUID, meetingFolderURL: URL, startedAt: Date) async
    func stop() async
}

@MainActor
final class MeetingScreenObservationCaptureController: MeetingScreenObservationCapturing {
    private let service: MeetingScreenObservationCaptureService

    init(service: MeetingScreenObservationCaptureService) {
        self.service = service
    }

    func start(meetingID: UUID, meetingFolderURL: URL, startedAt: Date) async {
        await service.start(meetingID: meetingID, meetingFolderURL: meetingFolderURL, startedAt: startedAt)
    }

    func stop() async {
        await service.stop()
    }
}
```

- [ ] **Step 4: Wire into `AppViewModel`**

Add property:

```swift
private let screenObservationCapturer: (any MeetingScreenObservationCapturing)?
```

Add init parameter:

```swift
screenObservationCapturer: (any MeetingScreenObservationCapturing)? = nil,
```

Assign it:

```swift
self.screenObservationCapturer = screenObservationCapturer
```

After `recordingService.startRecording(...)` succeeds in `startRecording()`, add:

```swift
await screenObservationCapturer?.start(
    meetingID: meetingID,
    meetingFolderURL: artifacts.meetingFolderURL,
    startedAt: startedAt
)
```

After `recordingService.stopRecording()` succeeds in `stopRecording()`, before clearing state, add:

```swift
await screenObservationCapturer?.stop()
```

Also call `await screenObservationCapturer?.stop()` in the startup failure cleanup path after `recordingService.stopRecording()`.

- [ ] **Step 5: Wire native implementation in `QuickMeetingApp`**

Create:

```swift
let screenObservationRecorder = NativeScreenSnapshotRecorder(
    meetingFileStore: meetingFileStore,
    attendeeNamesProvider: { meetingID in
        await MainActor.run {
            (try? meetingStore.fetchMeeting(id: meetingID).attendeeNames) ?? []
        }
    }
)
let screenObservationCaptureService = MeetingScreenObservationCaptureService(
    recorder: screenObservationRecorder,
    observationSink: screenObservationStore,
    interval: 12
)
let screenObservationCaptureController = MeetingScreenObservationCaptureController(
    service: screenObservationCaptureService
)
```

Pass `screenObservationCaptureController` into `AppViewModel`.

- [ ] **Step 6: Run focused tests and verify GREEN**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/AppViewModelTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS.

- [ ] **Step 7: Commit Task 8**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/QuickMeetingApp.swift QuickMeeting/Services/ScreenSpeakerSuggestions/MeetingScreenObservationCaptureService.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "Capture screen observations during recording"
```

---

### Task 9: UI Suggestion Card And Screenshot Preview

**Files:**
- Modify: `QuickMeeting/ContentView.swift`
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Test: `QuickMeetingTests/MeetingDetailViewSpeakerIdentityTests.swift`

- [ ] **Step 1: Add failing UI helper tests**

Append to `QuickMeetingTests/MeetingDetailViewSpeakerIdentityTests.swift`:

```swift
@Test
func suggestionForSpeakerReturnsPendingSuggestionForSpeakerID() {
    let suggestion = SpeakerIdentitySuggestion(
        meetingID: UUID(),
        speakerID: "speaker-1",
        proposedName: "Masha",
        confidence: .high,
        reason: "Seen in active tile",
        evidenceImageRelativePath: "screen-observations/0001.jpg",
        evidenceThumbnailRelativePath: nil,
        observationID: UUID(),
        capturedAtOffset: 2
    )

    #expect(speakerSuggestion(for: "speaker-1", in: [suggestion]) == suggestion)
    #expect(speakerSuggestion(for: "speaker-2", in: [suggestion]) == nil)
}

@Test
func confidenceLabelIsHumanReadable() {
    #expect(speakerSuggestionConfidenceText(.high) == "High")
    #expect(speakerSuggestionConfidenceText(.medium) == "Medium")
    #expect(speakerSuggestionConfidenceText(.low) == "Low")
}
```

- [ ] **Step 2: Run tests and verify RED**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingDetailViewSpeakerIdentityTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: FAIL because UI helper functions do not exist.

- [ ] **Step 3: Add helper functions**

Add near other nonisolated helpers in `MeetingDetailView.swift`:

```swift
nonisolated func speakerSuggestion(
    for speakerID: String,
    in suggestions: [SpeakerIdentitySuggestion]
) -> SpeakerIdentitySuggestion? {
    suggestions.first { $0.speakerID == speakerID && $0.status == .pending }
}

nonisolated func speakerSuggestionConfidenceText(_ confidence: SpeakerIdentitySuggestionConfidence) -> String {
    switch confidence {
    case .high: "High"
    case .medium: "Medium"
    case .low: "Low"
    }
}
```

- [ ] **Step 4: Extend `MeetingDetailView` inputs**

Add properties:

```swift
let speakerSuggestions: [SpeakerIdentitySuggestion]
let onAcceptSpeakerSuggestion: (SpeakerIdentitySuggestion) -> Void
let onDismissSpeakerSuggestion: (SpeakerIdentitySuggestion) -> Void
```

Update `ContentView` call:

```swift
speakerSuggestions: appViewModel.pendingSpeakerSuggestions(for: selectedMeeting.id),
onAcceptSpeakerSuggestion: { suggestion in
    Task {
        do {
            try await appViewModel.renameSpeaker(
                meetingID: selectedMeeting.id,
                speakerID: suggestion.speakerID,
                displayName: suggestion.proposedName
            )
            appViewModel.acceptSpeakerSuggestion(suggestion)
        } catch {}
    }
},
onDismissSpeakerSuggestion: { suggestion in
    appViewModel.dismissSpeakerSuggestion(suggestion)
},
```

- [ ] **Step 5: Render card in rename popover**

Change `renamePopover(speakerID:)` to show the card before `TextField`:

```swift
if let suggestion = speakerSuggestion(for: speakerID, in: speakerSuggestions) {
    speakerSuggestionCard(suggestion)
}
```

Add view:

```swift
@ViewBuilder
private func speakerSuggestionCard(_ suggestion: SpeakerIdentitySuggestion) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(QMTheme.sage)
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggested: \(suggestion.proposedName)")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(QMTheme.ink)
                Text("\(suggestion.reason) · \(speakerSuggestionConfidenceText(suggestion.confidence))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(QMTheme.secondary)
            }
            Spacer(minLength: 0)
        }

        HStack(spacing: 8) {
            Button {
                previewedSpeakerSuggestion = suggestion
            } label: {
                Label("Preview", systemImage: "photo")
            }
            .buttonStyle(.borderless)

            Spacer(minLength: 0)

            Button {
                onDismissSpeakerSuggestion(suggestion)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss suggestion")

            Button {
                onAcceptSpeakerSuggestion(suggestion)
                renameOpenSegmentID = nil
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .help("Accept suggestion")
        }
    }
    .padding(10)
    .background(QMTheme.chip, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(QMTheme.cardBorder, lineWidth: 1))
}
```

Add state:

```swift
@State private var previewedSpeakerSuggestion: SpeakerIdentitySuggestion?
```

Add sheet/popover:

```swift
.sheet(item: $previewedSpeakerSuggestion) { suggestion in
    SpeakerSuggestionPreviewWindow(
        meeting: meeting,
        suggestion: suggestion
    )
}
```

Add preview view in same file:

```swift
private struct SpeakerSuggestionPreviewWindow: View {
    let meeting: Meeting
    let suggestion: SpeakerIdentitySuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(suggestion.proposedName)
                .font(.system(size: 16, weight: .semibold))
            Text(suggestion.reason)
                .font(.system(size: 12))
                .foregroundStyle(QMTheme.secondary)
            if let image = evidenceImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 520, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Screenshot is unavailable.")
                    .foregroundStyle(QMTheme.secondary)
                    .frame(width: 520, height: 160)
            }
        }
        .padding(16)
    }

    private var evidenceImage: NSImage? {
        let meetingFolder = URL(fileURLWithPath: meeting.audioFilePath).deletingLastPathComponent()
        return NSImage(contentsOf: meetingFolder.appendingPathComponent(suggestion.evidenceImageRelativePath))
    }
}
```

- [ ] **Step 6: Run UI helper tests and build**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/MeetingDetailViewSpeakerIdentityTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS.

- [ ] **Step 7: Commit Task 9**

```bash
git add QuickMeeting/ContentView.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeetingTests/MeetingDetailViewSpeakerIdentityTests.swift
git commit -m "Show speaker identity suggestions"
```

---

### Task 10: Verification And Manual Kontur Talk QA

**Files:**
- Modify only if verification finds issues.

- [ ] **Step 1: Run focused suggestion tests**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/SpeakerIdentitySuggestionServiceTests -only-testing:QuickMeetingTests/ScreenObservationStoreTests -only-testing:QuickMeetingTests/MeetingScreenObservationCaptureServiceTests -only-testing:QuickMeetingTests/KonturTalkScreenAnalyzerTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS.

- [ ] **Step 2: Run AppViewModel and UI helper tests**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingDetailViewSpeakerIdentityTests -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS.

- [ ] **Step 3: Run a full test pass if focused tests are clean**

```bash
xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -quiet | rg "error:|warning:|passed|failed|Executed|BUILD"
```

Expected: PASS. If the full pass is too slow, record the focused test evidence and the reason full pass was not completed.

- [ ] **Step 4: Manual QA in Kontur Talk**

Use a test meeting in `https://kontur.ru/talk` with non-sensitive content.

1. Start a QuickMeeting recording.
2. Speak as one participant while Kontur Talk visibly highlights that tile.
3. Stop recording.
4. Transcribe the meeting.
5. Open the transcript speaker popover.
6. Confirm the suggestion card appears only as a suggestion.
7. Open the screenshot preview.
8. Accept the suggestion and confirm the speaker rename persists.
9. Change the calendar meeting to one with a different attendee list.
10. Confirm old pending suggestions disappear and new suggestions recompute from stored observations.

- [ ] **Step 5: Commit any verification fixes**

If fixes were required:

```bash
git add QuickMeeting QuickMeetingTests
git commit -m "Polish screen speaker suggestions"
```

If no fixes were required, do not create an empty commit.
