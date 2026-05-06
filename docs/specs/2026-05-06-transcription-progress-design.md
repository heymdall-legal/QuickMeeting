# Transcription Progress Reporting Design

## Summary

This design adds live progress reporting to the meeting transcription process. The first version shows a backend-driven percentage for the currently transcribing meeting inside the meeting detail screen only.

The percentage is transient runtime state, not persisted meeting metadata. The existing `Meeting` lifecycle remains responsible for durable status transitions such as `recorded`, `transcribing`, `completed`, and `failed`.

## Scope

### In Scope

- live transcription percentage sourced from the transcription backend
- progress shown only in `MeetingDetailView`
- a dedicated transcribing UI state in the transcript pane
- transient app-state progress tracking keyed by `meetingID`
- cleanup of progress state on success and failure
- tests for service progress orchestration and meeting detail rendering

### Out Of Scope

- transcript progress in the meeting list or app-wide banner
- partial transcript streaming while transcription is running
- persisting transcription percentage on `Meeting`
- approximate stage-based percentages
- support for multiple concurrent transcription jobs

## Product Decisions

- Progress should use real backend percentage reporting rather than estimated stage weights.
- Progress should be visible only in the selected meeting detail screen.
- The transcript pane should switch to a dedicated transcribing state while the job is active.
- The transcribing state should show a determinate progress bar and percentage text.
- The `Transcribe` action should be disabled while the meeting is already transcribing.

## Architecture

The progress feature should be implemented as transient orchestration state layered on top of the existing transcription pipeline.

The flow is:

1. User starts transcription from meeting detail.
2. `TranscriptionService` validates preconditions and marks the meeting as `transcribing`.
3. `TranscriptionService` registers the active meeting in a progress center with an initial value.
4. `WhisperKitTranscriptionBackend` forwards backend progress updates into that progress center through the service boundary.
5. `MeetingDetailView` observes the active meeting's progress and renders the dedicated transcribing UI.
6. On completion or failure, the progress entry is removed and the meeting transitions to its durable final status.

This keeps percentage reporting out of persistence and aligned with the existing separation between durable meeting state and transient runtime UI state.

## Components

### TranscriptionProgressCenter

Add a focused observable type that owns in-flight transcription progress keyed by `meetingID`.

Responsibilities:

- register a progress entry when transcription starts
- update progress values during backend execution
- remove progress entries when jobs finish or fail
- expose the current progress value for UI consumers

This type should only model live runtime state. It should not write to SwiftData or attempt to recover progress after app relaunch.

### TranscriptionService

`TranscriptionService` remains the orchestration entry point and gains responsibility for wiring backend updates into the progress center.

Responsibilities:

- create the progress entry once a transcription job has actually started
- pass a progress reporter into the backend
- clamp and forward progress updates
- clear progress state on all exit paths
- preserve the single-active-transcription rule

`TranscriptionService` should own lifecycle cleanup so the UI never has to guess whether progress is stale.

### WhisperTranscriptionBackend

The backend protocol should grow a progress-aware contract. The implementation can extend `TranscriptionRequest` with a callback or accept a separate `onProgress` parameter, but the contract must support repeated percentage updates during a single transcription run.

Responsibilities:

- emit normalized progress updates for the current transcription run
- continue returning the existing structured `TranscriptionResult`
- keep backend-specific runtime details isolated from the service and UI layers

### WhisperKitTranscriptionBackend

`WhisperKitTranscriptionBackend` should adapt WhisperKit's progress reporting into the app's normalized `0...1` range and forward those updates through the backend contract.

Rules:

- clamp emitted values into `0...1`
- ignore regressive updates if WhisperKit emits noisy or out-of-order callbacks
- preserve existing final transcript behavior even if progress updates are sparse

### MeetingDetailView

`MeetingDetailView` should consume the selected meeting's transient progress value and use it only when the meeting is in the `transcribing` state.

Expected behavior:

- replace the current empty transcript state with a dedicated transcribing state
- show `Transcribing...` copy, a determinate progress bar, and percentage text
- keep the `Transcribe` button disabled while transcribing
- switch to the completed transcript view when the meeting finishes successfully

## Data Model

### Durable Meeting Data

`Meeting` and `MeetingStore` remain unchanged as the durable source of truth for:

- `status`
- `audioFilePath`
- `transcriptFilePath`
- `transcriptPreview`
- `updatedAt`

No `transcriptionProgress` field should be added to `Meeting`.

### Transient Progress Data

The live progress model should be minimal:

- `meetingID`
- `progress` as `Double` in the range `0...1`

This data lives only in memory for the duration of the transcription run.

## UI Integration

The transcript pane in meeting detail becomes stateful across three user-visible cases:

- not transcribed yet
- transcribing with progress
- transcript available

During transcription, the dedicated progress state should replace the current "Not transcribed yet" empty state. The view should not attempt to show partial transcript content in this version.

Because the scope is detail-only, no meeting list, sidebar row, or global banner progress should be added.

## Error Handling

Progress reporting must never block a valid transcription result and must never leave stale UI behind.

Rules:

- if transcription fails after progress has started, the progress entry must be removed
- if transcription succeeds, the progress entry must be removed before or as the meeting transitions to `completed`
- if backend progress callbacks are unavailable, the transcription job may still complete normally
- incoming percentages must be clamped into `0...1`
- regressive progress updates should be ignored

The existing meeting failure behavior remains the same:

- source audio is preserved
- failed meetings remain retryable
- user-facing transcription errors continue to come from `TranscriptionService`

## Testing

### Service Tests

- transcription creates a progress entry for the active meeting
- backend progress updates change the live progress value
- progress entries are cleared on successful completion
- progress entries are cleared on failure
- single-active-transcription enforcement still holds

### Backend Adapter Tests

- progress forwarded by `WhisperKitTranscriptionBackend` is normalized into `0...1`
- regressive or invalid values are filtered or clamped as designed

If WhisperKit is hard to isolate directly, these guarantees can be covered with a narrow adapter wrapper test instead of a full runtime integration test.

### View Tests

- a transcribing meeting renders the dedicated progress state
- the percentage label reflects the current live value
- the transcribe action remains disabled during transcription

## Implementation Notes

- Keep progress state separate from persistence to avoid frequent SwiftData writes.
- Prefer a small, focused progress center over expanding `AppViewModel` into a state container for transcription internals.
- Preserve existing `TranscriptionResult` and transcript artifact generation behavior.
- Keep the first version lean and avoid introducing streaming transcript text or broader progress surfaces.

## Recommended Next Step

After this spec is reviewed, the next step is to write an implementation plan covering:

- progress center design
- backend contract changes
- transcription service orchestration updates
- meeting detail UI updates
- tests
