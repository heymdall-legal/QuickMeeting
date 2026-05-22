# Recording Compression Design

## Summary

QuickMeeting currently writes each meeting recording as uncompressed canonical WAV audio. That makes recordings far larger than necessary for spoken meetings and mixed call audio. The new default should save recordings as AAC-encoded `audio.m4a` at `96 kbps` while preserving the existing capture, playback, and transcription workflow.

The intended outcome is:

- dramatically smaller recording files
- no meaningful drop in transcription quality for normal meetings
- no change to how existing saved `.wav` meetings are loaded
- minimal surface-area change outside the recording writer and artifact naming

## Goals

- Reduce recording storage size by switching new recordings from WAV to AAC in an `m4a` container
- Keep transcription behavior reliable for spoken meetings with mixed microphone and system audio
- Preserve compatibility with existing meetings that already store `.wav` audio paths
- Keep the implementation small, testable, and reversible

## Non-Goals

- Adding a user-facing recording quality setting
- Re-encoding historical recordings
- Changing the capture/mixing logic before the file writer
- Adding a post-processing compression pass after recording completes
- Optimizing separately for music capture or studio-quality archival audio

## Current State

Today `MeetingFileStore` creates meeting artifacts with an `audio.wav` path. `NativeAudioCapturePipeline` captures microphone and system audio, converts them into canonical PCM buffers, mixes them, and writes them using `CanonicalWAVAudioFileWriter`.

This is simple and transcription-friendly, but it is storage-inefficient. Long meetings can easily reach hundreds of megabytes because WAV stores uncompressed PCM audio.

Playback and transcription already consume the stored `audioFilePath` directly, which means they do not depend on reconstructing a hardcoded filename at read time.

## Desired Behavior

For newly created meetings:

- the audio artifact path should be `audio.m4a`
- the file contents should use AAC encoding
- the encoder should target `96 kbps`
- the rest of the app should continue treating the stored audio path as the source of truth

For existing meetings:

- stored `.wav` paths must continue to play and transcribe normally
- no migration is required because the persisted meeting already stores the concrete file path

## Why `m4a` With AAC

The main problem is not sampling quality inside the capture pipeline; it is the on-disk storage format. AAC in an `m4a` container is a practical default because:

- it is widely supported by Apple audio APIs
- it offers a large size reduction for speech-heavy recordings
- it should remain suitable for Whisper-based transcription at moderate bitrates

The selected default is `96 kbps` because it is a conservative middle ground:

- much smaller than WAV
- safer than aggressively low speech bitrates
- appropriate for mixed meeting audio that may include voices from both microphone and system sources

## Proposed Architecture

### 1. Keep Capture and Mixing Unchanged

The current capture pipeline should continue to:

- receive audio sample buffers from ScreenCaptureKit
- convert them into canonical PCM buffers
- mix microphone and system audio into a single canonical stream

This preserves the existing behavior and keeps the format change isolated to the file-writing boundary.

### 2. Replace the WAV-Specific Writer

`CanonicalWAVAudioFileWriter` should be replaced with a writer that stores AAC-encoded `m4a` output while continuing to accept canonical PCM `AVAudioPCMBuffer` input.

Expected writer responsibilities:

- create the parent folder if needed
- remove any stale file at the output path
- configure `AVAudioFile` for AAC output in an `m4a` container
- write incoming PCM buffers incrementally
- finish cleanly when recording stops

The pipeline should not need to know encoder details beyond the writer implementation.

### 3. Update Artifact Creation

`MeetingFileStore` should create new meeting artifacts with `audio.m4a` instead of `audio.wav`.

This is the only place where new meeting filenames need to change. Because the meeting persists the full `audioFilePath`, downstream readers can stay format-agnostic.

### 4. Leave Transcription Entry Points Stable

`WhisperKitTranscriptionBackend` should continue receiving `request.audioFileURL.path` unchanged.

The first implementation should assume WhisperKit can consume the compressed file through the same path-based API. This keeps the integration small and lets real verification determine whether any compatibility layer is needed.

## Reliability Strategy for Transcription

The primary reliability concern is not the `m4a` extension itself, but overly aggressive compression. This design avoids that by:

- using AAC rather than a more fragile or exotic codec
- choosing a moderate bitrate of `96 kbps`
- keeping the pre-encode capture and mixing path unchanged

Potential outcomes:

- expected case: transcription quality remains effectively unchanged for normal meetings
- degraded case: if WhisperKit or the underlying decode path struggles with direct `m4a` input, transcription may fail or regress on some files

The implementation should optimize for the expected case first and verify it with targeted tests plus a manual recording/transcription check.

## Compatibility

No data migration is required.

Existing persisted meetings already contain the exact `audioFilePath`. That means:

- old meetings can keep pointing at `.wav`
- new meetings can point at `.m4a`
- playback and transcription should continue to operate on whichever path is stored

This mixed-format compatibility is acceptable because the storage model is already path-based rather than extension-derived.

## Failure Handling

If AAC writer initialization fails, recording startup should fail the same way the current WAV writer failure would fail. No fallback to WAV should be added in the first implementation because:

- it would complicate expectations around output format
- it would make test outcomes less deterministic
- a hard failure is easier to diagnose than a silent format switch

If later verification shows that transcription cannot reliably process recorded `m4a` files, the follow-up fallback should be added at transcription time, not recording time. The preferred fallback would be:

- decode the stored `m4a`
- write a temporary PCM file for transcription only
- keep the user-facing recording artifact compressed

That fallback is intentionally deferred unless verification proves it is necessary.

## Testing Strategy

Implementation should follow a focused red-green path.

### Unit Tests

- Update `MeetingFileStoreTests` to expect `audio.m4a` for new artifacts
- Add or update recording pipeline tests so the native pipeline can still start and stop cleanly with the new writer
- Preserve existing tests that prove stored arbitrary audio paths continue to flow through the meeting and transcription models

### Verification Scope

Use narrow verification only:

- targeted `QuickMeetingTests/MeetingFileStoreTests`
- targeted recording pipeline tests in `QuickMeetingTests/AppViewModelTests`
- any focused playback or transcription test only if the code path changes require it

### Manual Sanity Check

After the code change, record a short meeting sample and confirm:

- the output file is `audio.m4a`
- the file size is materially smaller than before
- playback still works
- transcription still completes successfully

## Risks and Trade-Offs

### Risk: WhisperKit Input Compatibility

The largest unknown is whether the current transcription backend path handles `m4a` recordings as smoothly as `wav` in this app environment.

Mitigation:

- keep the code change narrow
- verify with a real local recording
- add a transcription-time decode fallback only if needed

### Risk: Encoded Output Settings

If the AAC settings are too aggressive, speech artifacts could reduce transcription quality.

Mitigation:

- start at `96 kbps`, not a lower bitrate
- avoid introducing extra resampling or filtering changes in the same patch

### Trade-Off: Slightly More Complex Writer

WAV writing is simpler than AAC writing. Moving to compressed output increases writer configuration complexity, but it is still the smallest place to absorb that complexity because the rest of the pipeline can remain unchanged.

## Implementation Outline

1. Update the artifact filename from `audio.wav` to `audio.m4a`
2. Replace the WAV writer with an AAC `m4a` writer configured for `96 kbps`
3. Update focused tests to reflect the new artifact filename and successful recording lifecycle
4. Verify recording, playback, and transcription behavior with narrow automated coverage and a manual sanity check
