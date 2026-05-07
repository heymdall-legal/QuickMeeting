# Meeting Database Storage Design

## Summary

QuickMeeting currently splits meeting persistence across SwiftData and the filesystem. Meeting metadata lives in the database, while transcript artifacts and editable transcript structure live in per-meeting files on disk. This design replaces that split model with a single persistence boundary for meeting data: all meeting data is stored in SwiftData except for the canonical `audio.wav` recording, which remains on disk.

This is an intentional breaking storage change. There is no migration plan for existing meetings or transcript files. Existing local meeting data may be discarded.

## Goals

- Make SwiftData the single source of truth for all meeting data except raw audio.
- Keep only `audio.wav` on disk as the canonical recording artifact.
- Remove transcript markdown and transcript JSON sidecar files from the persistence model.
- Store transcript structure in the database so speaker rename and future transcript features operate on canonical persisted data.
- Simplify application code by removing file-backed transcript read and write flows.

## Non-Goals

- Migrating existing transcript files or meeting records into the new schema.
- Adding transcript export in this change.
- Changing the recording pipeline or audio file format.
- Introducing full-text transcript search or advanced transcript editing beyond the current speaker rename behavior.

## Recommended Approach

Use `Meeting` as the single aggregate root for persisted meeting data. The meeting record owns:

- meeting metadata
- recording state and timestamps
- `audioFilePath`
- transcript preview metadata if retained
- structured transcript data: speakers and segments

The canonical transcript representation is structured data, not rendered markdown. Transcript markdown or plain text is derived on demand from stored speakers and segments when the UI needs to display it.

## Architecture

### Aggregate Boundary

`Meeting` remains the only top-level persisted meeting model. All non-audio meeting data is stored under this aggregate boundary.

`audioFilePath` continues to point to the on-disk `audio.wav` file. No other meeting-managed files are required for normal app behavior.

### Transcript Data Model

Transcript data is stored as structured meeting-owned persistence data:

- speakers
- segments
- optional preview text

The transcript source of truth is the persisted speaker and segment collection. Rendered markdown is not stored in the database.

The design intentionally avoids duplicate persisted transcript representations. If a transcript can be derived from speakers and segments, it should not also be stored as a canonical rendered string.

### Model Changes

The `Meeting` model changes in these ways:

- Keep `audioFilePath`.
- Remove `transcriptFilePath`.
- Keep or recompute `transcriptPreview` depending on implementation convenience.
- Add persisted transcript speaker data owned by the meeting.
- Add persisted transcript segment data owned by the meeting.

The exact SwiftData representation can be either embedded meeting-owned models or directly persisted meeting-owned fields, but the ownership boundary stays the same: transcript data belongs to one meeting and is not shared.

### Service Boundary Changes

`MeetingStore` becomes the persistence boundary for all meeting and transcript data. It should own:

- meeting creation
- recording completion updates
- transcription state changes
- transcript persistence
- speaker rename updates
- meeting deletion

`MeetingTranscriptStore` should stop acting as a filesystem sidecar reader and writer. If it remains as a type, it should become a database-backed transcript helper layered on top of `MeetingStore` or be folded into `MeetingStore` if the extra abstraction no longer earns its keep.

`TranscriptionArtifactWriter` should no longer be responsible for writing canonical transcript artifacts to disk. Any rendering logic that remains useful should be retained only as an in-memory formatter for UI display or future export.

## Workflow Changes

### Recording

Recording start and stop are largely unchanged:

1. Create the meeting record in SwiftData.
2. Create the meeting folder only as needed for the audio file location.
3. Record and finalize `audio.wav`.
4. Update the meeting with completion metadata.

The meeting folder no longer exists to hold transcript artifacts. Its only required purpose is to contain the audio file.

### Transcription

The transcription flow changes from file-backed artifact creation to database persistence:

1. Load `audio.wav` from `audioFilePath`.
2. Run transcription and diarization.
3. Produce a structured transcript result containing speakers and segments.
4. Persist that transcript structure directly to the meeting record through `MeetingStore`.
5. Update meeting status and preview metadata.

The flow does not write `transcript.md` or `transcript.json`.

### Transcript Display

The detail view and transcript helpers render transcript content from stored segments at read time.

Expected read path:

1. Load the meeting from SwiftData.
2. Read stored speakers and segments.
3. Render transcript markdown or plain text in memory.
4. Display the rendered content.

This keeps one canonical persisted transcript representation while allowing the UI to keep the current display style.

### Speaker Rename

Speaker rename becomes a database update:

1. Fetch the target meeting transcript data.
2. Update the matching speaker display name in persisted transcript state.
3. Save the meeting.
4. Let transcript rendering reflect the new speaker name automatically.

No transcript file regeneration step is required.

### Deletion

Meeting deletion removes:

- the SwiftData meeting record and its transcript data
- the meeting audio file or containing folder on disk

No transcript cleanup logic is needed because transcript artifacts are no longer stored on disk.

## Data Reset Strategy

This change assumes a clean break from the current storage layout.

Rules:

- No migration code is required.
- No compatibility reads from legacy transcript files are required.
- No fallback behavior for older transcript paths is required.
- Existing local meeting data can be wiped or ignored during rollout.

Implementation can favor the cleanest code path over backwards compatibility.

## Error Handling

### Recording Failures

Recording failure behavior remains unchanged in principle:

- if meeting creation succeeded but recording startup failed, perform best-effort cleanup
- if audio recording had already started, preserve or clean up according to the existing rollback rules

This design does not change the audio failure model.

### Transcription Failures

Transcription failures should behave consistently with retranscription semantics:

- starting transcription clears or replaces any existing stored transcript state for that meeting
- if transcription fails after the new run starts, the meeting should end in `failed`
- the app should not leave behind partial transcript files because none are written

The implementation should choose one explicit policy for previously completed transcripts during retranscription and keep it consistent. Recommended policy: starting a new transcription replaces prior transcript data for that meeting.

### Transcript Read Failures

Transcript rendering should degrade gracefully:

- if no transcript data exists, show the existing empty/not-transcribed state
- if persisted transcript data cannot be rendered, show an unavailable/error state

The user-facing error should describe the transcript as unavailable rather than exposing storage internals.

### Speaker Rename Failures

Speaker rename failures become meeting or transcript persistence failures rather than file-not-found failures. The UI should continue surfacing a friendly rename error message without referencing missing sidecar files.

## Testing

### Persistence Tests

Update persistence coverage to verify:

- meetings persist without `transcriptFilePath`
- transcript speakers and segments persist with the meeting
- transcription completion stores structured transcript data in SwiftData
- retranscription clears or replaces existing transcript data according to the chosen policy

### Transcript Behavior Tests

Update transcript tests to verify:

- transcript rendering is derived from stored speakers and segments
- speaker rename updates persisted transcript state
- rendered transcript output reflects renamed speakers without relying on regenerated files

### Service Tests

Update transcription service tests to verify:

- transcription persists transcript structure through the database
- no transcript artifact files are written
- meeting status and preview behavior remain correct

### Deletion Tests

Update deletion tests to verify:

- deleting a meeting removes its database record
- deleting a meeting removes only the audio artifact from disk
- transcript deletion is implicit in database record removal

## Documentation Follow-Up

The broader architecture docs should be updated to remove the assumption that transcript artifacts are canonical files on disk. After this design is implemented, the documented storage boundary should be:

- database for all meeting metadata and transcript data
- filesystem for `audio.wav` only

## Open Implementation Choice

One implementation detail remains flexible:

- whether `transcriptPreview` stays as stored derived metadata or is fully computed on demand

Recommendation:

Keep `transcriptPreview` only if it materially simplifies list rendering or preserves current UI behavior with minimal cost. Otherwise, derive it from segments the same way full transcript text is derived.
