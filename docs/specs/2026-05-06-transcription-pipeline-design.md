# Transcription Pipeline Design

## Summary

This design adds a manual transcription pipeline for already recorded meetings in the macOS app. The first version only transcribes audio already attached to a `Meeting`, writes a plain-text transcript artifact into the meeting folder, and allows only one active transcription job app-wide.

The implementation should be shaped so diarization can be added later without redesigning the service boundary. To support that, the transcription backend should return a structured in-memory result with segment data even though the only persisted artifact in this version is `transcript.txt`.

## Scope

### In Scope

- manual transcription started from meeting detail
- transcription of the canonical `audio.wav` already owned by a `Meeting`
- plain-text transcript persistence in the meeting folder
- meeting status updates for transcription lifecycle
- single active transcription job app-wide
- data types that can grow into diarization later

### Out Of Scope

- importing arbitrary external audio files
- automatic transcription after recording stops
- multiple concurrent transcription jobs
- transcript diarization in the first shipped version
- structured transcript persistence such as JSON sidecars
- transcript export outside the app-managed meeting folder

## Product Decisions

- The user starts transcription manually from an existing meeting detail view.
- The canonical transcript artifact is plain text only.
- Only one transcription job may run at a time across the app.
- The app transcribes only meetings that already exist in the library.
- The design should preserve a clean path to future diarization support.

## Architecture

The transcription feature should be implemented as an orchestration service that sits between the UI, meeting persistence, file artifacts, and the Whisper runtime.

The flow is:

1. User selects a recorded meeting and starts transcription.
2. `TranscriptionService` validates preconditions.
3. `TranscriptionService` marks the meeting as `transcribing`.
4. A backend abstraction runs Whisper on the meeting's `audio.wav`.
5. The structured result is converted into `transcript.txt`.
6. Meeting metadata is updated with transcript path, preview, and final status.
7. If any step fails, the meeting is marked `failed` and the source audio remains untouched.

This keeps transcription independent from recording and preserves the existing design principle that recording and transcription are separate jobs.

## Components

### TranscriptionService

`TranscriptionService` is the app-facing entry point. It is responsible for:

- accepting a transcription request for a `Meeting`
- enforcing the single-active-transcription rule
- validating that the meeting is transcribable
- resolving the selected installed model
- updating meeting status through persistence helpers
- calling the backend
- writing transcript artifacts
- mapping failures into user-facing service errors

This service should own orchestration rather than backend details.

### WhisperTranscriptionBackend

`WhisperTranscriptionBackend` is a protocol boundary around the transcription runtime. It should accept:

- audio file location
- selected model identity or resolved model reference

It should return a structured `TranscriptionResult` rather than plain text so the backend contract remains stable when diarization or richer transcript views are added later.

### TranscriptionArtifactWriter

`TranscriptionArtifactWriter` is responsible for converting a `TranscriptionResult` into persisted artifacts inside the meeting folder.

For the first version it only writes:

- `transcript.txt`

Later it may also write:

- structured transcript sidecars
- diarization metadata
- alternate export-ready artifacts

This keeps file generation logic out of `TranscriptionService`.

### MeetingStore Transcription Updates

`MeetingStore` should gain focused transcription lifecycle methods instead of scattering persistence updates across the service. The exact method names can evolve, but the responsibilities should cover:

- mark meeting as transcribing
- mark meeting as completed with transcript metadata
- mark meeting as failed

This preserves a single place for meeting persistence rules and makes the workflow easier to test.

## Data Model

### Meeting Persistence

The existing `Meeting` model should remain the main indexed record. For this feature it should continue to store:

- `status`
- `audioFilePath`
- `transcriptFilePath`
- `transcriptPreview`
- `updatedAt`

No structured transcript segments should be stored directly on `Meeting` in this version.

### In-Memory Transcription Result

The backend result should be structured even though persistence is plain text only.

Conceptually:

- `TranscriptionResult`
  - `fullText: String`
  - `segments: [TranscriptSegment]`

- `TranscriptSegment`
  - stable `id`
  - `text`
  - optional `startTime`
  - optional `endTime`
  - optional future `speakerID`

The implementation does not need to persist speaker information now, but the type shape should reserve room for it. This is the main diarization-readiness decision in the design.

### Transcript Preview

`transcriptPreview` should be derived from transcript content generated by the pipeline rather than hand-authored UI state. The preview can remain a short leading excerpt of the final plain-text transcript.

## Transcribable State Rules

The service should allow transcription only when all of the following are true:

- no other transcription is currently active
- the meeting exists
- the meeting is in a transcribable state such as `recorded` or `failed`
- the audio file exists on disk
- a default installed transcription model is available

The service should reject:

- meetings still in `recording`
- meetings already in `transcribing`
- requests made while another app-wide transcription is active

If later product requirements want retranscription for `completed` meetings, that can be added as an explicit policy decision rather than assumed now.

## Storage And Artifact Layout

The canonical transcript artifact for this version is:

- `<meeting folder>/transcript.txt`

The meeting folder remains the source location for all large artifacts owned by the app. The transcript should be written next to `audio.wav` and referenced from `Meeting.transcriptFilePath`.

No external export location or additional sidecar file should be introduced in this version.

## UI Integration

The first UI entry point should be the meeting detail screen.

Expected behavior:

- recorded meetings show a `Transcribe` action
- while a transcription is active for that meeting, the UI reflects `transcribing`
- meetings with completed transcripts can later expose transcript viewing UX
- if transcription fails, the meeting remains visible and retryable

This feature should not introduce automatic transcription triggers or a separate queue management screen.

## Error Handling

The design should keep failures explicit and preserve source artifacts.

Failures that should be handled cleanly:

- no installed default model
- missing meeting audio file
- another transcription already active
- backend transcription failure
- transcript artifact write failure
- persistence update failure

Rules:

- the source `audio.wav` is never deleted automatically
- a failed transcription attempt does not corrupt existing audio
- the meeting should move to `failed` after a started job fails
- user-facing error messaging should come from `TranscriptionService`, not backend-specific details

## Testing

Tests should focus on orchestration, persistence, and failure handling.

### Core Success Case

- transcribing a recorded meeting writes `transcript.txt`
- transcript path is saved on the meeting
- transcript preview is saved on the meeting
- meeting status changes from `recorded` to `transcribing` to `completed`

### Validation Failures

- transcription fails cleanly when no default installed model exists
- transcription fails cleanly when the audio file is missing
- transcription rejects meetings in non-transcribable states
- transcription rejects a second request while another job is active

### Runtime Failures

- backend failure marks the meeting `failed`
- artifact writer failure marks the meeting `failed`
- source audio remains intact after any failure

### Extensibility Guardrails

- the backend contract returns structured segments even when persistence is plain text only
- transcript flattening into plain text is covered by tests so later diarization work can change formatting deliberately rather than accidentally

## Implementation Notes

- Follow the existing architectural pattern of isolating third-party runtime details behind internal protocols.
- Prefer small, focused types over a single large service file.
- Keep persistence logic centralized in `MeetingStore`.
- Keep the first release lean and avoid introducing a general background job system.

## Recommended Next Step

After this spec is approved, the next step is to write an implementation plan for:

- transcription domain types
- backend abstraction
- artifact writing
- meeting store lifecycle updates
- app wiring and UI trigger
- tests
