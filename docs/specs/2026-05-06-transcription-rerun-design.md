# Transcription Rerun Design

## Summary

This design allows users to rerun transcription for meetings that already have a completed transcript. When a user starts a rerun, the app should warn that the existing transcript will be overwritten. After confirmation and successful transcription start, the old transcript metadata should be cleared immediately and the meeting should enter the normal transcription flow again.

If the rerun succeeds, the new transcript replaces the old one. If it fails, the meeting should end in the `failed` state with no transcript metadata preserved from the previous run.

## Scope

### In Scope

- rerunning transcription for meetings in the `completed` state
- showing a warning before overwriting an existing transcript
- clearing transcript metadata immediately after confirmation and valid job start
- reusing the existing transcription progress and failure flows
- tests for rerun eligibility and destructive reset behavior

### Out Of Scope

- preserving or restoring the previous transcript after rerun failure
- adding transcript version history
- introducing a separate rerun-specific status
- changing the global single-transcription-at-a-time rule

## Product Decisions

- The `Transcribe` action remains the entry point for both first-time transcription and reruns.
- Completed meetings should allow the user to start transcription again.
- Starting a rerun for a completed meeting must show a warning first.
- Confirming the warning should allow the app to start a destructive rerun, and transcript metadata should clear as soon as that rerun officially starts.
- Canceling the warning should leave the meeting unchanged.
- If rerun fails, the meeting should show `failed` with no transcript content retained.

## UX Flow

### Recorded Or Failed Meetings

- Selecting `Transcribe` starts transcription immediately.
- No overwrite warning is shown because there is no completed transcript to replace.

### Completed Meetings

- Selecting `Transcribe` shows a confirmation alert.
- The alert explains that the existing transcript will be overwritten.
- `Cancel` dismisses the alert with no data changes.
- Confirming the action starts retranscription.

### After Confirmation

- Once the service has validated the request and starts the job, the meeting's transcript metadata is cleared immediately.
- The meeting enters the existing `transcribing` state.
- The detail screen switches from transcript content to the in-progress transcription UI.

### Completion And Failure

- On success, the meeting receives the newly written transcript metadata and moves back to `completed`.
- On failure, the meeting moves to `failed` and remains without transcript metadata.

## Architecture

The rerun feature should reuse the existing transcription pipeline rather than introduce a separate workflow. The main change is that a transcription start now needs to support both initial transcription and destructive replacement of an existing transcript.

The flow is:

1. User taps `Transcribe` in meeting detail.
2. If the meeting is `completed`, the UI presents an overwrite warning.
3. After confirmation, `AppViewModel` requests transcription through `TranscriptionService`.
4. `TranscriptionService` validates that the meeting is eligible, the audio file exists, no other transcription is active, and a default model is available.
5. After validation succeeds, `MeetingStore.startTranscription` clears transcript metadata and marks the meeting `transcribing`.
6. The existing backend, progress, artifact-writing, and completion logic run unchanged.
7. On success, the new transcript metadata is saved. On failure, the meeting is marked `failed`.

## Component Changes

### MeetingDetailView

`MeetingDetailView` should gain a second confirmation alert for transcription reruns.

Responsibilities:

- detect whether the current meeting is a completed transcript candidate for overwrite confirmation
- show the warning only for completed meetings
- invoke `onTranscribe` directly for `recorded` and `failed` meetings
- invoke `onTranscribe` only after confirmation for `completed` meetings

The delete confirmation pattern already exists in this view, so the rerun warning should follow the same style.

### AppViewModel

`AppViewModel.canTranscribeMeeting` should allow meetings in:

- `recorded`
- `failed`
- `completed`

It should still reject:

- `recording`
- `transcribing`

`AppViewModel.transcribeMeeting` can remain the single async entry point. No rerun-specific method is required.

### TranscriptionService

`TranscriptionService` should treat `completed` meetings as transcribable alongside `recorded` and `failed`.

Validation order should remain important:

- reject another active transcription first
- fetch the meeting and check its state
- verify audio file presence
- verify installed default model availability

Only after these checks succeed should the service begin the transcription lifecycle in persistence. This prevents clearing a valid transcript because of a precondition failure.

### MeetingStore

`MeetingStore.startTranscription` should become the single persistence transition into `transcribing`, regardless of whether this is a first transcription or a rerun.

When called, it should:

- clear `transcriptFilePath`
- clear `transcriptPreview`
- update the meeting status to `transcribing`
- update `updatedAt`

This keeps destructive rerun behavior centralized in persistence rather than split between UI and service code.

### Meeting

`Meeting.beginTranscription` should support the reset behavior needed by `MeetingStore.startTranscription`.

The exact implementation can either:

- clear transcript metadata inside `beginTranscription`, or
- add a dedicated helper for destructive transcription start

The preferred outcome is not a specific method name but a clear invariant: once transcription starts, any old transcript metadata is gone.

## Data Rules

- `transcriptFilePath` and `transcriptPreview` are the durable indicators of transcript availability.
- Starting a rerun clears both fields immediately after the transcription request passes validation and officially starts.
- Failed reruns do not restore previous values.
- No additional persistence fields are needed for rerun state.

## Error Handling

The overwrite warning is a product-level confirmation, not the actual start of the destructive change.

Rules:

- canceling the warning must not change meeting data
- validation failures before transcription starts must not clear transcript metadata
- once transcription has officially started, old transcript metadata must already be cleared
- backend or artifact writer failures after start must leave the meeting in `failed`
- the existing transcription error alert should continue to present failures from `TranscriptionService`

This preserves a clean distinction between:

- pre-start validation failures, which leave the old transcript intact
- post-start runtime failures, which leave the meeting failed and empty

## Testing

### Automated Tests

- `AppViewModelTests`: completed meetings are considered transcribable
- `TranscriptionServiceTests`: completed meetings can be retranscribed successfully
- `MeetingStoreTests`: starting transcription clears existing transcript metadata and marks the meeting `transcribing`
- `TranscriptionServiceTests`: validation failures for completed meetings do not clear transcript metadata because start never occurs

### Manual Verification

- a completed meeting displays transcript text before rerun
- tapping `Transcribe` on a completed meeting shows an overwrite warning
- canceling the warning keeps the existing transcript visible
- confirming the warning clears transcript content immediately and shows the transcribing progress UI
- a successful rerun replaces the transcript and returns the meeting to `completed`
- a failed rerun leaves the meeting in `failed` with no transcript content

## Implementation Notes

- Follow the existing meeting detail alert style rather than introducing a new interaction pattern.
- Keep rerun logic small by extending existing eligibility and persistence methods instead of adding a parallel retranscription system.
- Preserve the current single-active-transcription constraint and progress reporting flow.

## Recommended Next Step

After this spec is reviewed, the next step is to write an implementation plan that covers:

- UI confirmation changes in `MeetingDetailView`
- completed-meeting eligibility updates in `AppViewModel` and `TranscriptionService`
- destructive transcript reset behavior in `MeetingStore` and `Meeting`
- focused automated tests and manual verification
