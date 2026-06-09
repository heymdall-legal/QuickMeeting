# Sidecar Transcription Design

## Summary

This design moves the default transcription and diarization execution path out of the main macOS app process and into a bundled sidecar executable. The app will launch the bundled helper for each manual transcription request, stream machine-readable progress events from `stdout`, and persist the final structured transcript into the existing meeting data model.

The existing native Whisper and diarization implementation stays in the repository for now. This migration only changes the default wiring used by the app at runtime.

## Scope

### In Scope

- bundle the prebuilt sidecar executable with the app
- add a new sidecar-backed transcription service implementation
- make the sidecar-backed implementation the default runtime path
- parse streamed JSON progress and result events from the sidecar
- persist the sidecar result as `StoredTranscript`
- reuse the existing meeting status and progress UI behavior
- hardcode the Hugging Face token temporarily in app-side launch code
- keep the current model-management code and UI unchanged

### Out Of Scope

- removing the existing native transcription or diarization code
- adding a user-facing switch between native and sidecar execution
- moving Hugging Face token management into settings
- integrating known-speaker identification
- redesigning transcript persistence
- changing the manual transcription entry point in the UI

## Product Decisions

- Manual transcription remains a user-triggered action from the existing UI.
- Only one transcription job may run app-wide at a time.
- The bundled sidecar is the default implementation with no UI toggle.
- Existing model-management screens remain visible and unchanged during this phase.
- Known-speaker recognition support in the sidecar is intentionally unused for now.
- The Hugging Face token is temporarily hardcoded in the app and passed to the sidecar at launch.

## Architecture

The app should treat the sidecar as an implementation detail behind the existing `TranscriptionServicing` boundary.

The flow is:

1. User starts transcription for a recorded meeting.
2. The sidecar-backed service validates meeting state and audio availability.
3. The service marks the meeting as `transcribing` and begins progress tracking.
4. The service resolves the bundled executable from the app bundle.
5. The service launches the executable with the meeting audio path and runtime environment.
6. The service reads newline-delimited JSON events from `stdout`.
7. Progress events update `TranscriptionProgressCenter`.
8. A terminal `completed` event is converted into `StoredTranscript`.
9. The meeting is marked `completed` with the new transcript and preview text.
10. If the job fails after starting, the meeting is marked `failed`.

This keeps the UI and meeting persistence model stable while moving the heavy runtime work into a separate process.

## Components

### SidecarTranscriptionService

`SidecarTranscriptionService` becomes the new default app-facing transcription service. It is responsible for:

- enforcing the single-active-transcription rule
- validating the meeting and source audio file
- starting and finishing meeting progress tracking
- resolving the bundled executable path
- launching the sidecar process
- passing required arguments and environment variables
- decoding and reacting to streamed JSON events
- converting the final sidecar payload into `StoredTranscript`
- updating `MeetingStore` with success or failure state

It should own orchestration only. Process spawning and event decoding should remain factored into small helpers so the service can be tested without launching the real executable.

### Sidecar Process Launcher

A dedicated launcher helper should wrap `Process`, `Pipe`, and executable resolution. Its responsibilities are:

- resolve the sidecar executable URL from `Bundle.main`
- configure process arguments
- configure environment variables such as `HF_HOME`
- stream `stdout` lines back to the caller
- collect `stderr` for diagnostics when helpful
- surface launch and termination failures in a structured form

This isolates Foundation process details from the higher-level transcription workflow.

### Sidecar Event Decoder

A decoder helper should parse each `stdout` line as JSON and map it into internal event types. It should:

- ignore non-JSON or malformed lines rather than failing immediately
- recognize the documented terminal events: `completed` and `error`
- preserve the sidecar's `reason` text for user-facing failures
- convert integer percentage fields into normalized `Double` progress values

This allows the service to focus on workflow policy instead of line-by-line decoding details.

### MeetingStore Integration

`MeetingStore` should continue to own lifecycle persistence:

- `startTranscription`
- `completeTranscription`
- `failTranscription`

No schema change is required for this migration because the sidecar result can be stored using the existing structured transcript path.

## Bundling Strategy

The sidecar distribution is not a standalone file. The app must bundle the full contents of `/Users/heymdall/Developer/whisper-test/dist/example`, including:

- the `example` executable
- the sibling `_internal` directory that contains the embedded Python runtime and shared-library dependencies

The bundled layout must preserve that sibling relationship so the executable can resolve `_internal` exactly as it does in the source distribution.

Runtime expectations:

- the app resolves the executable through `Bundle.main`
- the app preserves the adjacent `_internal` directory in the final app bundle
- the app executes the bundled binary in place
- the app does not copy the sidecar payload into Application Support on first launch
- the app does not download or install the sidecar itself

The design assumes the bundled artifact is already executable when included in the app product. If Xcode resource handling drops execute permissions, that should be corrected as part of integration.

## Runtime Contract

The service should invoke the sidecar with:

- `--input-file <meeting audio path>`
- `--hf-token <hardcoded token>`

It should not pass:

- `--known-speakers-file`

It may later pass optional language or prompt arguments, but that is not part of this migration.

The app should also set:

- `HF_HOME=<Application Support>/QuickMeeting/HuggingFace`

This gives the sidecar a stable cache location for downloaded models and avoids repeated cold-start downloads across runs.

## Event Mapping

The sidecar emits newline-delimited JSON events on `stdout`. The app should treat these events as the primary success and progress contract.

Mapping:

- `running`
  Starts transcription progress tracking if not already started.

- `downloading`
  Updates transcription progress using `percent / 100`.
  Download progress should share the existing transcription progress channel rather than introducing a third UI state.

- `transcribing`
  Updates transcription progress using `percent / 100`.

- `diarization`
  Starts diarization tracking if needed and updates diarization progress using `percent / 100`.

- `completed`
  Terminates the stream successfully and provides the final speakers and segments payload.

- `error`
  Terminates the stream as a failure and surfaces the provided `reason`.

If the process exits without emitting a terminal event, the service should treat that as a failure even if some progress events were seen.

## Transcript Mapping

The sidecar `completed` payload should be converted into the app's existing transcript model.

### Speakers

Each sidecar speaker becomes a `TranscriptSpeaker`:

- `id` maps directly from the sidecar speaker `id`
- `displayName` defaults to sequential UI-friendly labels such as `Speaker 1`, `Speaker 2`, in the order first encountered

The sidecar's `matched_id`, `probability`, and `centroid` fields are ignored in this phase.

### Segments

Each sidecar segment becomes a `TranscriptSegment`:

- generate a stable local `UUID` when constructing the segment
- map `text`
- map `start` to `startTime`
- map `end` to `endTime`
- map `speaker` to `speakerID`

The resulting `StoredTranscript.fullText` remains the source for the meeting preview text, matching current app behavior.

## Default Wiring

`QuickMeetingApp` should construct the new sidecar-backed service as the default `transcriptionService`.

The current native `TranscriptionService`, `WhisperKitTranscriptionBackend`, and `DefaultTranscriptDiarizer` remain in the codebase unchanged. They are no longer the default runtime path, but they are not removed or rewritten in this phase.

## Error Handling

The migration should preserve existing failure behavior as closely as possible.

Failures to handle explicitly:

- meeting is not in a transcribable state
- meeting audio file is missing
- another transcription job is already active
- bundled sidecar executable cannot be found
- sidecar process fails to launch
- sidecar emits a terminal `error` event
- sidecar exits without a terminal `completed` event
- final result payload is structurally invalid
- meeting persistence fails after a started job

Rules:

- once the meeting has been marked `transcribing`, any downstream failure should best-effort mark it `failed`
- progress entries should always be cleaned up when the job ends
- existing audio files are never modified or deleted by transcription
- existing completed transcripts should only be replaced after successful sidecar completion
- user-visible error text should come from structured service errors or the sidecar `reason` when available

## Testing

Tests should cover the new service at the orchestration boundary without launching the real sidecar binary.

### Core Success Cases

- a recorded meeting can be transcribed through streamed sidecar events
- a completed terminal event persists speakers, segments, preview text, and `completed` status
- an existing completed transcript is replaced only after successful completion

### Validation Failures

- missing audio file is rejected before process launch
- non-transcribable meeting states are rejected
- a second request while one is active is rejected
- missing bundled executable fails cleanly

### Runtime Failures

- a terminal `error` event marks the meeting `failed`
- process launch failure marks the meeting `failed` once a job has started
- process exit without a terminal event marks the meeting `failed`
- malformed JSON lines are ignored if a valid terminal event still arrives
- invalid terminal payload shape fails cleanly

### Progress Behavior

- `downloading` and `transcribing` update transcription progress monotonically
- `diarization` updates diarization progress monotonically
- both progress channels are cleared after success
- both progress channels are cleared after failure

## Migration Notes

- This phase intentionally keeps the model-management UI even though the sidecar path does not use the selected local Whisper model.
- This phase intentionally ignores known-speaker identification data from the sidecar.
- A later cleanup phase can remove the dormant native runtime path and repurpose settings once the sidecar path is proven stable.

## Recommended Next Step

Write an implementation plan for the sidecar-backed service, bundling changes, and targeted tests.
