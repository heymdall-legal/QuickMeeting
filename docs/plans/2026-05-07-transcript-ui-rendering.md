**Goal:** Replace markdown-style transcript rendering in the meeting detail view with a richer, selectable transcript UI that groups consecutive speaker segments under bold headings and optionally shows non-selectable segment start times.

**Architecture:** Keep `StoredTranscript` as the source of truth and change the UI transcript path to load structured transcript data instead of markdown text. Render the transcript inside one scrollable AppKit-backed surface whose document view contains a non-selectable timestamp column and one selectable `NSTextView`, while `MeetingDetailView` owns a local `showSegmentTimes` toggle and passes it into the renderer.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing, `xcodebuild`

---

## File Structure

- Modify: `QuickMeeting/Support/MeetingTranscriptContent.swift`
  Purpose: replace markdown-oriented UI transcript content with structured display content, add speaker-run grouping helpers, and add timestamp formatting helpers.
- Modify: `QuickMeeting/Views/TranscriptTextView.swift`
  Purpose: replace the plain `NSTextView` wrapper with a transcript renderer that builds one scrollable document view containing a timestamp column and a selectable text view.
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
  Purpose: switch transcript loading to the new structured content path and add a local `Show segment times` toggle in the right sidebar.
- Modify: `QuickMeetingTests/MeetingTranscriptContentTests.swift`
  Purpose: cover structured transcript loading, speaker grouping, trimmed text, timestamp formatting, and attributed transcript text generation.

### Task 1: Reshape transcript content into structured UI data

**Files:**
- Modify: `QuickMeeting/Support/MeetingTranscriptContent.swift`
- Test: `QuickMeetingTests/MeetingTranscriptContentTests.swift`

- [ ] **Step 1: Write the failing structured-content tests**

```swift
@Test
func storedTranscriptLoadsStructuredDisplayContent() {
    let content = loadMeetingTranscriptContent(
        from: StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Masha")],
            segments: [
                TranscriptSegment(text: "  Hello world  ", startTime: 5, endTime: 7, speakerID: "speaker-1")
            ]
        )
    )

    #expect(
        content == .transcript(
            MeetingTranscriptDisplay(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Masha")],
                segments: [
                    TranscriptSegment(text: "Hello world", startTime: 5, endTime: 7, speakerID: "speaker-1")
                ]
            )
        )
    )
}

@Test
func meetingStoredTranscriptSortsPersistedSegmentsChronologically() throws {
    let meeting = Meeting(
        title: "Sync",
        startedAt: Date(timeIntervalSince1970: 1_714_561_200),
        status: .completed,
        audioFilePath: "/tmp/audio.wav",
        transcriptSpeakers: [PersistedTranscriptSpeaker(id: "speaker-1", displayName: "Masha")],
        transcriptSegments: [
            PersistedTranscriptSegment(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                text: "Second sentence",
                startTime: 12,
                endTime: 18,
                speakerID: "speaker-1"
            ),
            PersistedTranscriptSegment(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                text: "First sentence",
                startTime: 3,
                endTime: 9,
                speakerID: "speaker-1"
            ),
        ]
    )

    let transcript = try #require(meeting.storedTranscript)

    #expect(
        loadMeetingTranscriptContent(from: transcript) == .transcript(
            MeetingTranscriptDisplay(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Masha")],
                segments: [
                    TranscriptSegment(text: "First sentence", startTime: 3, endTime: 9, speakerID: "speaker-1"),
                    TranscriptSegment(text: "Second sentence", startTime: 12, endTime: 18, speakerID: "speaker-1")
                ]
            )
        )
    )
}
```

- [ ] **Step 2: Run the focused transcript-content tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcript-ui "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: FAIL because `MeetingTranscriptContent` still exposes `.text(String)` and `loadMeetingTranscriptContent(from:)` still returns markdown text.

- [ ] **Step 3: Implement the structured transcript display model**

```swift
enum MeetingTranscriptContent: Equatable {
    case transcript(MeetingTranscriptDisplay)
    case notAvailable
    case unavailable(message: String)
}

struct MeetingTranscriptDisplay: Equatable {
    let speakers: [TranscriptSpeaker]
    let segments: [TranscriptSegment]
}

func loadMeetingTranscriptContent(from transcript: StoredTranscript?) -> MeetingTranscriptContent {
    guard let transcript else {
        return .notAvailable
    }

    let trimmedSegments = transcript.segments.compactMap { segment -> TranscriptSegment? in
        let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        return TranscriptSegment(
            id: segment.id,
            text: trimmedText,
            startTime: segment.startTime,
            endTime: segment.endTime,
            speakerID: segment.speakerID
        )
    }

    guard !trimmedSegments.isEmpty else {
        return .notAvailable
    }

    return .transcript(
        MeetingTranscriptDisplay(
            speakers: transcript.speakers,
            segments: trimmedSegments
        )
    )
}
```

- [ ] **Step 4: Re-run the focused transcript-content tests**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcript-ui "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: PASS for the new structured-content assertions, with existing nil and reload-key tests still green.

- [ ] **Step 5: Commit the content-model change**

```bash
git add QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "refactor: load structured transcript UI content"
```

### Task 2: Add speaker-run grouping and transcript formatting helpers

**Files:**
- Modify: `QuickMeeting/Support/MeetingTranscriptContent.swift`
- Test: `QuickMeetingTests/MeetingTranscriptContentTests.swift`

- [ ] **Step 1: Write the failing grouping and timestamp-formatting tests**

```swift
@Test
func displayRunsGroupConsecutiveSegmentsByResolvedSpeaker() {
    let display = MeetingTranscriptDisplay(
        speakers: [
            TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
            TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2")
        ],
        segments: [
            TranscriptSegment(text: "First", startTime: 0, endTime: 1, speakerID: "speaker-1"),
            TranscriptSegment(text: "Second", startTime: 2, endTime: 3, speakerID: "speaker-1"),
            TranscriptSegment(text: "Third", startTime: 4, endTime: 5, speakerID: "speaker-2"),
            TranscriptSegment(text: "Fourth", startTime: 6, endTime: 7, speakerID: nil)
        ]
    )

    #expect(transcriptDisplayRuns(from: display) == [
        TranscriptDisplayRun(
            speakerName: "Speaker 1",
            segments: [
                TranscriptSegment(text: "First", startTime: 0, endTime: 1, speakerID: "speaker-1"),
                TranscriptSegment(text: "Second", startTime: 2, endTime: 3, speakerID: "speaker-1")
            ]
        ),
        TranscriptDisplayRun(
            speakerName: "Speaker 2",
            segments: [
                TranscriptSegment(text: "Third", startTime: 4, endTime: 5, speakerID: "speaker-2")
            ]
        ),
        TranscriptDisplayRun(
            speakerName: nil,
            segments: [
                TranscriptSegment(text: "Fourth", startTime: 6, endTime: 7, speakerID: nil)
            ]
        )
    ])
}

@Test
func segmentTimestampTextUsesMinuteSecondFormatting() {
    #expect(segmentTimestampText(for: 0) == "0:00")
    #expect(segmentTimestampText(for: 9) == "0:09")
    #expect(segmentTimestampText(for: 65) == "1:05")
    #expect(segmentTimestampText(for: 3_661) == "1:01:01")
}
```

- [ ] **Step 2: Run the focused transcript-content tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcript-ui "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: FAIL because `TranscriptDisplayRun`, `transcriptDisplayRuns(from:)`, and `segmentTimestampText(for:)` do not exist yet.

- [ ] **Step 3: Implement the grouping and timestamp helpers**

```swift
struct TranscriptDisplayRun: Equatable {
    let speakerName: String?
    let segments: [TranscriptSegment]
}

func transcriptDisplayRuns(from display: MeetingTranscriptDisplay) -> [TranscriptDisplayRun] {
    let speakersByID = Dictionary(uniqueKeysWithValues: display.speakers.map { ($0.id, $0.displayName) })
    var runs = [TranscriptDisplayRun]()

    for segment in display.segments {
        let speakerName = segment.speakerID.flatMap { speakersByID[$0] }

        if let lastIndex = runs.indices.last, runs[lastIndex].speakerName == speakerName {
            runs[lastIndex].segments.append(segment)
        } else {
            runs.append(TranscriptDisplayRun(speakerName: speakerName, segments: [segment]))
        }
    }

    return runs
}

func segmentTimestampText(for startTime: TimeInterval) -> String {
    let totalSeconds = max(Int(startTime.rounded(.down)), 0)
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    return String(format: "%d:%02d", minutes, seconds)
}
```

- [ ] **Step 4: Re-run the focused transcript-content tests**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcript-ui "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: PASS for speaker-run grouping and timestamp formatting.

- [ ] **Step 5: Commit the transcript-display helpers**

```bash
git add QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "feat: add transcript speaker grouping helpers"
```

### Task 3: Build the rich transcript AppKit view

**Files:**
- Modify: `QuickMeeting/Views/TranscriptTextView.swift`
- Modify: `QuickMeeting/Support/MeetingTranscriptContent.swift`
- Test: `QuickMeetingTests/MeetingTranscriptContentTests.swift`

- [ ] **Step 1: Write the failing attributed-transcript tests**

```swift
#if canImport(AppKit)
@Test
func transcriptAttributedStringBuildsSpeakerHeadingsAndBodyText() {
    let display = MeetingTranscriptDisplay(
        speakers: [
            TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
            TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2")
        ],
        segments: [
            TranscriptSegment(text: "some words", startTime: 0, endTime: 1, speakerID: "speaker-1"),
            TranscriptSegment(text: "that is very important", startTime: 2, endTime: 3, speakerID: "speaker-1"),
            TranscriptSegment(text: "and so on", startTime: 4, endTime: 5, speakerID: "speaker-2")
        ]
    )

    let attributedString = makeTranscriptAttributedString(from: display)

    #expect(
        attributedString.string ==
            "Speaker 1\nsome words\nthat is very important\n\nSpeaker 2\nand so on"
    )
}

@Test
func transcriptAttributedStringUsesHeadlineWeightForSpeakerHeadings() throws {
    let display = MeetingTranscriptDisplay(
        speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
        segments: [TranscriptSegment(text: "Line one", startTime: 0, endTime: 1, speakerID: "speaker-1")]
    )

    let attributedString = makeTranscriptAttributedString(from: display)
    let headingFont = try #require(
        attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    )

    #expect(headingFont.fontDescriptor.symbolicTraits.contains(.bold))
}
#endif
```

- [ ] **Step 2: Run the focused transcript-content tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcript-ui "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: FAIL because `makeTranscriptAttributedString(from:)` still accepts `String` and cannot build grouped speaker headings.

- [ ] **Step 3: Implement the attributed transcript builder and rich document view**

```swift
func makeTranscriptAttributedString(from display: MeetingTranscriptDisplay) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let bodyParagraphStyle = NSMutableParagraphStyle()
    bodyParagraphStyle.lineSpacing = 6

    let headingParagraphStyle = NSMutableParagraphStyle()
    headingParagraphStyle.paragraphSpacing = 4

    let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.preferredFont(forTextStyle: .body),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: bodyParagraphStyle
    ]

    let headingAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.preferredFont(forTextStyle: .headline),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: headingParagraphStyle
    ]

    for (runIndex, run) in transcriptDisplayRuns(from: display).enumerated() {
        if let speakerName = run.speakerName {
            result.append(NSAttributedString(string: speakerName + "\n", attributes: headingAttributes))
        }

        for (segmentIndex, segment) in run.segments.enumerated() {
            result.append(NSAttributedString(string: segment.text, attributes: bodyAttributes))

            let isLastSegmentInRun = segmentIndex == run.segments.count - 1
            let isLastRun = runIndex == transcriptDisplayRuns(from: display).count - 1

            if !isLastSegmentInRun {
                result.append(NSAttributedString(string: "\n", attributes: bodyAttributes))
            } else if !isLastRun {
                result.append(NSAttributedString(string: "\n\n", attributes: bodyAttributes))
            }
        }
    }

    return result
}

struct TranscriptTextView: NSViewRepresentable {
    let display: MeetingTranscriptDisplay
    let showSegmentTimes: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        let documentView = TranscriptDocumentView(textView: textView)
        documentView.update(display: display, showSegmentTimes: showSegmentTimes)
        scrollView.documentView = documentView
        return scrollView
    }
}
```

Implementation notes for this step:

- `TranscriptDocumentView` should own one `NSTextView` for selectable transcript text and one vertical stack view for timestamp labels.
- The document view should rebuild the timestamp column from `display.segments` when `showSegmentTimes` changes.
- The text view should remain `isSelectable = true`, `isEditable = false`, `drawsBackground = false`.
- Timestamp labels should use `.caption1`-like sizing, `.secondaryLabelColor`, and `isSelectable = false`.

- [ ] **Step 4: Re-run the focused transcript-content tests**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcript-ui "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: PASS for grouped transcript text output, bold heading attributes, and existing helper coverage.

- [ ] **Step 5: Commit the rich transcript renderer**

```bash
git add QuickMeeting/Views/TranscriptTextView.swift QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "feat: render transcript with speaker headings"
```

### Task 4: Wire the transcript renderer into the meeting detail view

**Files:**
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeeting/Views/TranscriptTextView.swift`
- Test: `QuickMeetingTests/MeetingTranscriptContentTests.swift`

- [ ] **Step 1: Write the failing integration-oriented helper tests**

```swift
@Test
func loadMeetingTranscriptContentReturnsNotAvailableWhenTrimmedSegmentsAreEmpty() {
    let content = loadMeetingTranscriptContent(
        from: StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "   ", startTime: 0, endTime: 1, speakerID: "speaker-1")]
        )
    )

    #expect(content == .notAvailable)
}

#if canImport(AppKit)
@Test
func transcriptTextViewUpdatesDisplayedTranscriptText() {
    let firstDisplay = MeetingTranscriptDisplay(
        speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
        segments: [TranscriptSegment(text: "First line", startTime: 0, endTime: 1, speakerID: "speaker-1")]
    )
    let secondDisplay = MeetingTranscriptDisplay(
        speakers: [TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2")],
        segments: [TranscriptSegment(text: "Second line", startTime: 10, endTime: 11, speakerID: "speaker-2")]
    )

    let view = TranscriptTextView(display: firstDisplay, showSegmentTimes: false)
    let scrollView = view.makeNSView(context: .init())
    view.updateNSView(scrollView, context: .init())

    let updatedView = TranscriptTextView(display: secondDisplay, showSegmentTimes: true)
    updatedView.updateNSView(scrollView, context: .init())

    let documentView = try #require(scrollView.documentView as? TranscriptDocumentView)
    #expect(documentView.transcriptString == "Speaker 2\nSecond line")
    #expect(documentView.timestampStrings == ["0:10"])
}
#endif
```

- [ ] **Step 2: Run the focused transcript-content tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcript-ui "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: FAIL because `TranscriptTextView` does not yet expose the `display` and `showSegmentTimes` interface or update a custom document view.

- [ ] **Step 3: Update `MeetingDetailView` and finish the transcript-view integration**

```swift
@State private var transcriptContent: MeetingTranscriptContent = .notAvailable
@State private var showSegmentTimes = false

private var transcriptPane: some View {
    VStack(alignment: .leading, spacing: 20) {
        switch currentTranscriptPaneState {
        case .transcript:
            switch transcriptContent {
            case .transcript(let display):
                TranscriptTextView(display: display, showSegmentTimes: showSegmentTimes)
            case .notAvailable:
                transcriptEmptyState
            case .unavailable(let message):
                transcriptUnavailableState(message: message)
            }
        default:
            // keep existing progress and empty states
        }
    }
}

private var transcriptDisplaySection: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Transcript Display")
            .font(.headline)

        Toggle("Show segment times", isOn: $showSegmentTimes)
    }
}

private var sidebar: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            detailSection
            transcriptDisplaySection
            actionSection
            speakersSection
            filesSection
        }
    }
}
```

Implementation notes for this step:

- Keep `showSegmentTimes` local to `MeetingDetailView` and let it default to `false`.
- Do not add the toggle to any persistent settings model.
- Preserve the existing empty, unavailable, transcribing, and diarizing UI branches.

- [ ] **Step 4: Run the focused tests and then the broader transcript-related suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcript-ui "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: PASS for the transcript-content coverage, including the document-view update behavior.

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-transcript-ui "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests -only-testing:QuickMeetingTests/MeetingTranscriptionProgressDisplayTests -only-testing:QuickMeetingTests/MeetingStoreTests
```

Expected: PASS for transcript-content behavior with no regressions in transcript state or persistence helpers.

- [ ] **Step 5: Commit the meeting-detail integration**

```bash
git add QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/Views/TranscriptTextView.swift QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "feat: add optional segment times to transcript UI"
```

## Manual Verification

1. Open a completed meeting with diarized transcript data in the app.
2. Confirm the transcript renders as one continuous selectable surface rather than markdown headings.
3. Confirm consecutive segments for the same speaker share one bold heading.
4. Confirm segments are separated by a single line break.
5. Toggle `Show segment times` on and confirm a small gray timestamp column appears on the left.
6. Select and copy transcript text with timestamps visible and confirm the pasted text excludes timestamps.
7. Toggle `Show segment times` off and confirm the transcript text expands back to full width.
8. Switch away from the meeting detail view and return, then confirm `Show segment times` resets to hidden.

## Self-Review

- Spec coverage:
  - Structured transcript UI data: covered by Task 1.
  - Consecutive speaker headings: covered by Task 2 and Task 3.
  - Single selectable transcript surface: covered by Task 3 and manual verification.
  - Optional non-selectable timestamps: covered by Task 2, Task 3, and Task 4.
  - Local sidebar toggle hidden by default: covered by Task 4.
  - Export markdown unchanged: preserved by omission from modified files and called out in Task 1 and Task 4 implementation notes.
- Placeholder scan:
  - No `TBD`, `TODO`, or deferred “write tests later” steps remain.
- Type consistency:
  - The plan consistently uses `MeetingTranscriptDisplay`, `TranscriptDisplayRun`, `segmentTimestampText(for:)`, `TranscriptTextView(display:showSegmentTimes:)`, and `showSegmentTimes`.
