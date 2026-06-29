# Transcript Replica Editing Design

## Context

QuickMeeting stores transcripts as ordered `TranscriptSegment` values with text, optional timestamps, and an optional `speakerID`. The current meeting detail UI renders these segments as speaker bubbles and lets users rename speakers, but it does not let users correct diarization mistakes by moving text between speakers.

When diarization merges two voices into one segment, users need a lightweight way to split one displayed reply into two replies and assign the new reply to another speaker.

## Goals

- Let users edit transcript reply boundaries directly from the transcript bubble UI.
- Make `Enter` create a new reply at the cursor position.
- Make `Shift+Enter` insert a newline inside the current reply text.
- Let users merge a reply with the previous reply by pressing Backspace/Delete at the beginning of the reply.
- Let users assign the newly split reply to an existing or renamed speaker.
- Persist edits to the meeting transcript and keep Markdown export in sync through the existing store path.

## Non-Goals

- Do not implement audio-level word alignment or exact timestamp recalculation.
- Do not add drag-and-drop text movement.
- Do not redesign the transcript screen beyond the controls needed for editing.
- Do not change the sidecar transcription or diarization pipeline.

## UX Behavior

Each transcript bubble becomes editable. While the text editor is focused:

- `Enter` splits the current segment at the cursor.
  - Text before the cursor stays in the current segment.
  - Text after the cursor moves into a new segment inserted immediately after the current one.
  - If either side is empty after trimming whitespace, the split is ignored.
  - The new segment initially inherits the original `speakerID`.
  - After the split, the new segment is focused and opens the existing speaker rename/assignment popover so the user can choose another speaker.
- `Shift+Enter` inserts `\n` into the same segment.
- Backspace/Delete at cursor position `0` merges the current segment into the previous segment.
  - The previous segment keeps its `speakerID`, `startTime`, and position.
  - The current segment text is appended to the previous segment with a separating newline.
  - The current segment is removed.
  - If there is no previous segment, the key behaves normally.

Speaker assignment uses the existing speaker name popover pattern. Choosing a name for the newly split reply assigns the segment to that speaker. If the selected display name belongs to an existing speaker, the segment uses that speaker's ID. If the user enters a new name, the store creates a new transcript speaker and assigns the segment to it.

## Data Model

`TranscriptSegment` needs mutable persisted replacement operations, but the value type can remain immutable. The store layer should expose intent-level operations rather than letting the view rewrite the entire transcript:

- update a segment's text
- split a segment at a character offset
- merge a segment with its previous segment
- assign a segment to a speaker by display name or speaker ID

`PersistedTranscriptSegment` already stores `id`, `text`, `startTime`, `endTime`, and `speakerID`, so no schema migration is required for text edits, split, merge, or reassignment.

For timestamps:

- The original segment keeps its existing `startTime`.
- A newly split segment gets `startTime: nil` and `endTime: original.endTime`.
- The original segment's `endTime` becomes `nil` after split.
- Merge keeps the previous segment's `startTime` and uses the current segment's `endTime` when available.

This avoids pretending we know exact word timing after manual edits.

## Architecture

Add transcript editing operations to `MeetingTranscriptStoring`, implemented by `MeetingTranscriptStore` and `MeetingStore`. `AppViewModel` exposes async methods that call the store, update error state, and let `MeetingDetailView` reload via the existing meeting `updatedAt` reload key.

Keep editing state local to `MeetingDetailView`: focused segment ID, draft text, cursor-driven split/merge callbacks, and the segment that should open the speaker assignment popover after split. The view should not mutate SwiftData models directly.

For macOS text editing, use an `NSViewRepresentable` wrapper around `NSTextView` for each editable bubble so the app can distinguish `Enter`, `Shift+Enter`, and Backspace/Delete at the beginning of text reliably.

## Testing

Add focused tests for pure store behavior:

- splitting a segment inserts a new segment immediately after the original
- split ignores empty left or right sides
- merging a segment with the previous segment removes the current segment and preserves the previous speaker
- assigning a segment to an existing speaker changes only that segment's `speakerID`
- assigning a segment to a new name creates a speaker and assigns the segment

Add UI-support tests for keyboard policy if the key handling logic is factored into a small pure helper. Full AppKit key event testing is not required for the first pass.

Run targeted QuickMeeting tests first, then a broader focused test set if the store and view model changes pass.
