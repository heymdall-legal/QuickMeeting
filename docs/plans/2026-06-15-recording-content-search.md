**Goal:** Expand recordings search so a contiguous case-insensitive phrase can match meeting titles, user-named transcript speakers, or transcript segment text.

**Architecture:** Add a pure `meetingMatchesSearch(_:query:)` helper in `QuickMeeting/Support` so the complete search policy is testable without rendering SwiftUI. Keep `AppSidebarView` responsible only for applying that predicate to its meetings; read existing transcript data directly so title changes, speaker renames, and completed transcriptions are reflected immediately without a persisted index.

**Tech Stack:** Swift, SwiftUI, SwiftData model objects, Swift Testing, Xcode/macOS test runner, xcsift

---

### Task 1: Add the recording search predicate with full behavior coverage

**Files:**
- Create: `QuickMeeting/Support/MeetingSearch.swift`
- Create: `QuickMeetingTests/MeetingSearchTests.swift`

- [ ] **Step 1: Write the failing search contract tests**

Create `QuickMeetingTests/MeetingSearchTests.swift`:

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct MeetingSearchTests {
    @Test
    func emptyAndWhitespaceQueriesDoNotFilterMeeting() {
        let meeting = makeMeeting(title: "Weekly Product Sync")

        #expect(meetingMatchesSearch(meeting, query: ""))
        #expect(meetingMatchesSearch(meeting, query: "   \n"))
    }

    @Test
    func titleMatchesContiguousPhraseCaseInsensitively() {
        let meeting = makeMeeting(title: "Weekly Design Review")

        #expect(meetingMatchesSearch(meeting, query: "  DESIGN review  "))
        #expect(!meetingMatchesSearch(meeting, query: "design weekly"))
    }

    @Test
    func namedTranscriptSpeakerMatchesCaseInsensitively() {
        let meeting = makeMeeting(
            speakers: [
                PersistedTranscriptSpeaker(id: "speaker-1", displayName: "Masha Ivanova")
            ]
        )

        #expect(meetingMatchesSearch(meeting, query: "masha iva"))
    }

    @Test
    func placeholderTranscriptSpeakerDoesNotMatch() {
        let meeting = makeMeeting(
            speakers: [
                PersistedTranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")
            ]
        )

        #expect(!meetingMatchesSearch(meeting, query: "speaker 1"))
    }

    @Test
    func calendarAttendeeDoesNotMatch() {
        let meeting = makeMeeting(attendeeNames: ["Calendar Person"])

        #expect(!meetingMatchesSearch(meeting, query: "calendar person"))
    }

    @Test
    func transcriptSegmentMatchesContiguousPhraseCaseInsensitively() {
        let meeting = makeMeeting(
            segments: [
                PersistedTranscriptSegment(TranscriptSegment(
                    text: "The design review went well",
                    speakerID: "speaker-1"
                ))
            ]
        )

        #expect(meetingMatchesSearch(meeting, query: "DESIGN review"))
    }

    @Test
    func multiwordQueryDoesNotMatchSeparatedWordsWithinOneSegment() {
        let meeting = makeMeeting(
            segments: [
                PersistedTranscriptSegment(TranscriptSegment(
                    text: "Design decisions from the quarterly review",
                    speakerID: "speaker-1"
                ))
            ]
        )

        #expect(!meetingMatchesSearch(meeting, query: "design review"))
    }

    @Test
    func queryDoesNotCombineMatchesAcrossFieldsOrSegments() {
        let meeting = makeMeeting(
            title: "Design",
            segments: [
                PersistedTranscriptSegment(TranscriptSegment(text: "Review", speakerID: "speaker-1")),
                PersistedTranscriptSegment(TranscriptSegment(text: "Design", speakerID: "speaker-1"))
            ]
        )

        #expect(!meetingMatchesSearch(meeting, query: "design review"))
    }

    @Test
    func meetingWithoutTranscriptStillSearchesByTitleSafely() {
        let meeting = makeMeeting(title: "Roadmap Planning")

        #expect(meeting.storedTranscript == nil)
        #expect(meetingMatchesSearch(meeting, query: "roadmap"))
        #expect(!meetingMatchesSearch(meeting, query: "budget"))
    }

    private func makeMeeting(
        title: String = "Unrelated Meeting",
        speakers: [PersistedTranscriptSpeaker] = [],
        segments: [PersistedTranscriptSegment] = [],
        attendeeNames: [String] = []
    ) -> Meeting {
        Meeting(
            title: title,
            startedAt: Date(timeIntervalSince1970: 1_714_561_200),
            status: .completed,
            audioFilePath: "/tmp/audio.wav",
            transcriptSpeakers: speakers,
            transcriptSegments: segments,
            attendeeNames: attendeeNames
        )
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
rtk xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination "platform=macOS" \
  -derivedDataPath .derived-data-recording-search \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -only-testing:QuickMeetingTests/MeetingSearchTests \
  2>&1 | rtk xcsift -f toon -q
```

Expected: FAIL at compile time because `meetingMatchesSearch(_:query:)` does not exist.

- [ ] **Step 3: Implement the minimal pure predicate**

Create `QuickMeeting/Support/MeetingSearch.swift`:

```swift
import Foundation

func meetingMatchesSearch(_ meeting: Meeting, query: String) -> Bool {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else {
        return true
    }

    func containsQuery(_ value: String) -> Bool {
        value.range(of: normalizedQuery, options: .caseInsensitive) != nil
    }

    if containsQuery(meeting.title) {
        return true
    }

    guard let transcript = meeting.storedTranscript else {
        return false
    }

    if transcript.speakers.contains(where: {
        !QMSpeakerPalette.isUnnamed($0.displayName)
            && containsQuery($0.displayName)
    }) {
        return true
    }

    return transcript.segments.contains(where: { containsQuery($0.text) })
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run:

```bash
rtk xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination "platform=macOS" \
  -derivedDataPath .derived-data-recording-search \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -only-testing:QuickMeetingTests/MeetingSearchTests \
  2>&1 | rtk xcsift -f toon -q
```

Expected: PASS with all `MeetingSearchTests` tests successful and no compile errors.

- [ ] **Step 5: Commit the tested search helper**

```bash
rtk git add QuickMeeting/Support/MeetingSearch.swift QuickMeetingTests/MeetingSearchTests.swift
rtk git commit -m "Add recording content search matching"
```

### Task 2: Wire the recordings sidebar to the search predicate

**Files:**
- Modify: `QuickMeeting/Views/AppSidebarView.swift:286`
- Test: `QuickMeetingTests/MeetingSearchTests.swift`

- [ ] **Step 1: Replace the title-only filtering predicate**

Change `filteredMeetings` in `QuickMeeting/Views/AppSidebarView.swift` to:

```swift
private var filteredMeetings: [Meeting] {
    meetings.filter { meetingMatchesSearch($0, query: searchText) }
}
```

This preserves the existing `groupedMeetings` date grouping and meeting order while applying the tested search contract.

- [ ] **Step 2: Run the focused search tests after sidebar integration**

Run:

```bash
rtk xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination "platform=macOS" \
  -derivedDataPath .derived-data-recording-search \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -only-testing:QuickMeetingTests/MeetingSearchTests \
  2>&1 | rtk xcsift -f toon -q
```

Expected: PASS, confirming the helper still compiles in the app target and its behavior remains green.

- [ ] **Step 3: Run focused neighboring regressions**

Run:

```bash
rtk xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination "platform=macOS" \
  -derivedDataPath .derived-data-recording-search \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -only-testing:QuickMeetingTests/MeetingSearchTests \
  -only-testing:QuickMeetingTests/MeetingTranscriptContentTests \
  -only-testing:QuickMeetingTests/MeetingStoreTests \
  2>&1 | rtk xcsift -f toon -q
```

Expected: PASS for the search, transcript-content, and meeting-store suites with no build errors.

- [ ] **Step 4: Verify the final diff is scoped and clean**

Run:

```bash
rtk git diff --check
rtk git status --short
```

Expected: no whitespace errors; only `AppSidebarView.swift` is modified after the Task 1 commit.

- [ ] **Step 5: Commit the sidebar integration**

```bash
rtk git add QuickMeeting/Views/AppSidebarView.swift
rtk git commit -m "Use transcript content in recording search"
```
