## Goal

Make persisted meeting state crash-safe by storing only durable statuses in SwiftData. Transient lifecycle steps such as active recording and active transcription must not be treated as persisted truth, because the app can crash or be force-quit while work is still in progress.

## Problem

Today `Meeting.status` persists both durable outcomes and in-flight runtime states:

- `recording`
- `recorded`
- `transcribing`
- `completed`
- `failed`

This means the database can be left behind in an impossible state after an interruption. A meeting may remain forever marked as `recording` or `transcribing` even though no process is active anymore. The app has no durable source of truth to distinguish "currently running in this process" from "last saved before a crash."

## Product Decision

Recovery of interrupted recording state follows this rule:

- If the recording file exists on disk and has non-zero length, recover as `recorded`.
- Otherwise, recover as `failed`.

For interrupted transcription, the meeting should return to a durable, retryable state rather than stay in a transient state. Because transcription operates on an already-finished recording, interrupted transcription should recover to `recorded` after clearing the transient marker.

## Recommended Approach

Persist only durable statuses in the `Meeting` model:

- `recorded`
- `completed`
- `failed`

Treat active recording and active transcription as runtime-only state owned by in-memory services:

- `AppViewModel.recordingState` remains the source of truth for an active recording in the current app session.
- `TranscriptionProgressCenter` plus `TranscriptionService.activeMeetingID` remain the source of truth for an active transcription in the current app session.

The database should answer "what durable meeting artifact exists?" rather than "what was the app doing at the exact moment it last saved?"

## Data Model Design

### Persisted status

`MeetingStatus` will become a durable-only enum:

- `recorded`
- `completed`
- `failed`

`recording` and `transcribing` will be removed from the persisted enum API.

### Legacy values

Existing rows may still contain raw persisted values of:

- `recording`
- `transcribing`

The app needs a recovery path that reads those legacy values and normalizes them to durable state before the rest of the UI and services rely on them.

## Recovery Design

Introduce a single recovery path in the persistence layer so stale transient states are repaired consistently.

### Legacy `recording`

When a meeting row contains legacy `recording`:

1. Check whether `audioFilePath` exists.
2. Check whether the file size is greater than zero.
3. If both are true, convert the meeting to `recorded`.
4. Otherwise convert the meeting to `failed`.
5. Save the repaired meeting.

This repair may also set `updatedAt` to the repair timestamp so the meeting reflects that the durable state changed after recovery.

### Legacy `transcribing`

When a meeting row contains legacy `transcribing`:

1. Convert the meeting to `recorded`.
2. Preserve any existing transcript artifacts unless the current re-transcription flow intentionally clears them.
3. Save the repaired meeting.

This treats an interrupted transcription as "recording still exists and can be retried" rather than a permanent failure.

## Behavioral Changes

### Meeting creation

`MeetingStore.createMeeting` should stop persisting `recording`.

Instead, a newly created meeting should be written with a durable crash-safe status. The simplest durable interpretation is:

- create the meeting as `failed` before recording starts successfully
- transition to `recorded` only once recording stops successfully

This ensures an interruption during startup cannot leave behind a fake active status. If startup fails and no usable audio file exists, the meeting remains `failed` until cleanup deletes it. If a partial but non-empty file exists and cleanup does not remove it, recovery rules still produce a coherent state.

### Recording runtime state

The live "recording now" indicator should come only from `AppViewModel.recordingState` and related runtime state. Persisted meeting rows should never be used to infer that a recording is currently active after restart.

### Transcription runtime state

The live "transcribing now" indicator should come only from the transcription runtime state:

- `TranscriptionProgressCenter`
- `TranscriptionService.activeMeetingID`

Persisted meeting rows should never remain in a transcription-in-progress state across launches.

### Status-based UI behavior

Any UI or service logic that currently checks `meeting.status` for `.recording` or `.transcribing` must be updated to use:

- durable persisted status for historical state
- runtime state for active operations in the current process

Examples:

- "Can transcribe" should continue to allow `recorded`, `failed`, and `completed`.
- Meeting detail status text should show active transcription progress from runtime tracking, not from persisted `transcribing`.
- Delete/stop protections for an active recording should use the active runtime meeting ID, not persisted status.

## Persistence API Changes

The persistence layer should become responsible for normalization of legacy rows.

Likely API changes:

- add a helper to resolve or repair raw persisted status values
- ensure `fetchMeeting(id:)` returns a normalized meeting before consumers inspect status
- add a bulk normalization path for fetching meeting lists, if needed by the current UI architecture

The important constraint is that consumers should not need to remember to repair stale rows manually in multiple places.

## Migration Strategy

This does not require a heavyweight schema migration if `statusRawValue` remains a string and the code simply stops exposing transient enum cases publicly.

Migration is behavioral:

1. Update `MeetingStatus` to durable-only cases.
2. Add legacy-status recovery logic near the model/store boundary.
3. Normalize existing rows lazily on fetch, or eagerly on app launch if there is already a suitable startup hook.
4. Remove assumptions elsewhere that persisted status can represent active work.

Lazy repair on fetch is preferred unless the app already has a central startup path for persistence maintenance, because it minimizes change surface and guarantees that repaired objects are saved when first touched.

## Error Handling

- Invalid or unknown raw status values should still surface as a model error unless explicitly mapped.
- File-inspection failures during legacy `recording` recovery should conservatively resolve to `failed`.
- Recovery should be best-effort but deterministic; a failed repair must not leave the meeting reported as active recording/transcription.

## Testing Plan

Add or update tests around:

- creating a meeting no longer persists `recording`
- recording completion still persists `recorded`
- legacy `recording` repairs to `recorded` when the file exists and has non-zero size
- legacy `recording` repairs to `failed` when the file is missing
- legacy `recording` repairs to `failed` when the file is empty
- legacy `transcribing` repairs to `recorded`
- transcription start no longer persists `transcribing`
- existing transcription completion and failure flows still persist `completed` and `failed`
- UI/runtime checks still reflect active recording and transcription from in-memory state

Focused regression coverage should center on `MeetingStore`, `Meeting`, `TranscriptionService`, and any status presentation helpers.

## Risks And Mitigations

- Risk: removing enum cases could break code paths that still switch over transient states.
  Mitigation: update switch sites in one pass and rely on compiler exhaustiveness to find stale assumptions.

- Risk: creating a meeting as `failed` before recording starts may briefly represent a startup-in-progress item as failed if observed mid-start.
  Mitigation: runtime recording state already owns the active-session UI; persisted rows are historical durability only.

- Risk: transcript metadata clearing behavior during re-transcription could be coupled to the old persisted `transcribing` status.
  Mitigation: keep transcript clearing in the explicit "start transcription" mutation, but do not use the persisted status to represent the active run.

## Success Criteria

- After force quit or crash, no meeting remains permanently stuck in `recording` or `transcribing`.
- Reopening the app deterministically repairs any legacy transient status rows.
- Recording and transcription progress still appear correctly during the active app session.
- Users can retry interrupted work without manual database repair.
