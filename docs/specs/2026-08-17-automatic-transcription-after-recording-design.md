# Automatic transcription after recording

## Goal

Allow a user to opt in to starting transcription automatically after a
recording finishes successfully, without changing the default manual workflow.

## Behaviour

- The feature is disabled by default, including for existing installations.
- It applies to both manually started and automatically started recordings.
- After the recorder stops successfully and the meeting is persisted as
  recorded, the app starts the existing transcription workflow for that
  meeting.
- The recording lifecycle is not blocked while transcription runs.
- If recording cannot be stopped or finished, transcription is not started.
- A transcription failure uses the same error state as a manually requested
  transcription; the finished recording remains available for retry.

## Interface

The Transcription section of Settings adds a toggle named `Automatically
transcribe after recording` with supporting text that it starts transcription
when a recording ends. The toggle is initially off.

## Implementation boundaries

- `TranscriptionPipelineOptions` gains `isAutomaticTranscriptionEnabled`.
- `TranscriptionSettingsStore` persists that option in `UserDefaults` and
  returns `false` when the key is absent.
- `TranscriptionSettingsViewModel` exposes and updates the option, preserving
  the existing language, CTC, and LLM-correction values when saving.
- `AppViewModel` receives the transcription settings store so it can evaluate
  the flag after the successful recording-finish transition. When enabled, it
  creates a task that invokes the existing `transcribeMeeting(_:)` method for
  the just-finished meeting.
- The existing `TranscriptionProgressCenter` continues to serialize active
  transcription work; no queue or concurrent-transcription feature is added.

## Error handling

The automatic path only begins after `MeetingStore.finishRecording` succeeds.
Errors from the transcription service are caught by the existing
`transcribeMeeting(_:)` method and are exposed through its existing UI error
state. Starting an automatic task after recording cleanup must not change the
recording state back from idle.

## Testing

- Settings-store tests cover the false default and persistence of the flag.
- Settings-view-model tests cover loading and toggling it while preserving
  other pipeline options.
- App-view-model tests cover starting transcription after a successful manual
  and automatic recording when enabled, and not starting it when disabled or
  when stopping fails.

## Scope

This change adds an opt-in trigger only. It does not alter the transcription
pipeline, introduce a persistent job queue, retry failed transcription, or
change the manual Transcribe and Re-transcribe controls.
