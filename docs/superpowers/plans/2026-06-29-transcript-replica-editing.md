# Transcript Replica Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build inline transcript reply editing so Enter splits a reply, Shift+Enter inserts a newline, Backspace/Delete at the beginning merges with the previous reply, and split replies can be assigned to another speaker.

**Architecture:** Add intent-level transcript editing methods to `MeetingTranscriptStoring`, implemented by `MeetingTranscriptStore` and `MeetingStore`, then expose them through `AppViewModel`. Keep UI editing state local to `MeetingDetailView` and use a small AppKit-backed editable text view for reliable macOS key handling.

**Tech Stack:** Swift, SwiftData, SwiftUI, AppKit `NSTextView`, Swift Testing, QuickMeeting Xcode project.

---

### Task 1: Store Transcript Editing Operations

**Files:**
- Modify: `QuickMeeting/Services/Transcription/MeetingTranscriptStore.swift`
- Modify: `QuickMeeting/Services/MeetingStore.swift`
- Modify: `QuickMeeting/Models/Meeting.swift`
- Test: `QuickMeetingTests/MeetingTranscriptStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Add tests to `MeetingTranscriptStoreTests` for `updateSegmentText`, `splitSegment`, `mergeSegmentWithPrevious`, and `assignSegment`.

Expected API:

```swift
try harness.transcriptStore.updateSegmentText(segmentID: segmentID, text: "Edited", in: meeting.id)
try harness.transcriptStore.splitSegment(segmentID: segmentID, at: 5, in: meeting.id)
try harness.transcriptStore.mergeSegmentWithPrevious(segmentID: secondSegmentID, in: meeting.id)
try harness.transcriptStore.assignSegment(segmentID: segmentID, toSpeakerNamed: "Masha", in: meeting.id)
```

- [ ] **Step 2: Run targeted tests and confirm RED**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting-Test -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests -quiet 2>&1 | rg "error:|warning:|passed|failed|Executed [0-9]+ tests|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: compile failure because the new transcript editing APIs do not exist yet.

- [ ] **Step 3: Implement store operations**

Implement operations in `MeetingStore` and forward them through `MeetingTranscriptStore`. Add `Meeting.replaceTranscriptSegments(_:updatedAt:)` or focused mutation helpers if needed so SwiftData relationship ordering remains explicit.

Rules:
- update text trims only outer newlines, keeps intentional internal newlines
- split ignores empty left/right sides after trimming whitespace/newlines
- split inserts the new segment immediately after the original in persisted order
- merge keeps the previous segment's speaker and start time
- assigning by display name reuses an existing speaker case-insensitively or creates a new `TranscriptSpeakerLabelSource.userAssigned` speaker

- [ ] **Step 4: Run targeted tests and confirm GREEN**

Run the same `xcodebuild test` command. Expected: `MeetingTranscriptStoreTests` pass.

### Task 2: ViewModel Bridge

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write failing AppViewModel tests**

Add a stub `MeetingTranscriptStoring` implementation that records calls for segment text update, split, merge, and assign. Test that `AppViewModel` trims speaker names, forwards meeting/segment IDs, and stores `renameSpeakerErrorMessage` on failure.

- [ ] **Step 2: Run targeted tests and confirm RED**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting-Test -only-testing:QuickMeetingTests/AppViewModelTests -quiet 2>&1 | rg "error:|warning:|passed|failed|Executed [0-9]+ tests|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: compile failure because the new `AppViewModel` methods do not exist.

- [ ] **Step 3: Implement AppViewModel methods**

Add async throwing methods:

```swift
func updateTranscriptSegmentText(meetingID: UUID, segmentID: UUID, text: String) async throws
func splitTranscriptSegment(meetingID: UUID, segmentID: UUID, cursorOffset: Int) async throws -> TranscriptSegment?
func mergeTranscriptSegmentWithPrevious(meetingID: UUID, segmentID: UUID) async throws -> TranscriptSegment?
func assignTranscriptSegment(meetingID: UUID, segmentID: UUID, speakerName: String) async throws
```

Use the same error state as speaker editing for now: `renameSpeakerErrorMessage`.

- [ ] **Step 4: Run targeted tests and confirm GREEN**

Run the same AppViewModel targeted command. Expected: tests pass.

### Task 3: Editable Transcript Bubble UI

**Files:**
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Create: `QuickMeeting/Views/EditableTranscriptTextView.swift`
- Test: `QuickMeetingTests/MeetingDetailViewSpeakerIdentityTests.swift` or new focused UI-support test file

- [ ] **Step 1: Write failing pure keyboard policy tests**

Extract pure helpers for text split/merge decisions, such as:

```swift
func splitTranscriptText(_ text: String, cursorOffset: Int) -> TranscriptTextSplit?
func mergedTranscriptText(previous: String, current: String) -> String
```

Test:
- valid cursor returns left/right text
- cursor at start/end returns nil
- Shift+Enter is treated as newline by the AppKit wrapper, not the split helper
- merge joins previous/current with one newline

- [ ] **Step 2: Run targeted tests and confirm RED**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting-Test -only-testing:QuickMeetingTests/MeetingDetailViewSpeakerIdentityTests -quiet 2>&1 | rg "error:|warning:|passed|failed|Executed [0-9]+ tests|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: compile failure because helper types/functions do not exist.

- [ ] **Step 3: Implement editable AppKit text view and wire bubble actions**

Create `EditableTranscriptTextView` as an `NSViewRepresentable` wrapping `NSTextView`.

Behavior:
- `insertNewline(_:)` calls `onSplit(cursorOffset)` for plain Enter
- `insertNewlineIgnoringFieldEditor(_:)` or Shift-modified return inserts `\n`
- `deleteBackward(_:)` and `deleteForward(_:)` at cursor `0` call `onMergeWithPrevious`
- text changes call `onTextChange`

Replace bubble `Text(bubble.text)` with the editable wrapper. Track draft text by segment ID, focus after split, and open the speaker assignment popover for the new segment.

- [ ] **Step 4: Run targeted UI-support tests and build**

Run the targeted test, then a compile build:

```bash
xcodebuild build -project QuickMeeting.xcodeproj -scheme QuickMeeting-Test -quiet 2>&1 | rg "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: build succeeds.

### Task 4: Final Targeted Regression

**Files:**
- Verify only.

- [ ] **Step 1: Run focused test set**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting-Test -only-testing:QuickMeetingTests/MeetingTranscriptStoreTests -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingDetailViewSpeakerIdentityTests -quiet 2>&1 | rg "error:|warning:|passed|failed|Executed [0-9]+ tests|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: all selected tests pass.

- [ ] **Step 2: Review diff**

Run:

```bash
git diff -- QuickMeeting QuickMeetingTests docs/superpowers/plans/2026-06-29-transcript-replica-editing.md
```

Expected: changes are scoped to transcript editing.
