# Meeting Audio Playback Design

## Goal

Add in-app playback for a saved meeting recording from the meeting detail screen so a user can review audio without leaving QuickMeeting.

## Scope

Included in this change:

- playback controls in the meeting detail view
- loading audio from the persisted `Meeting.audioFilePath`
- simple playback state shown in the UI
- friendly error handling when the file cannot be opened
- automated tests for playback state and missing-file behavior

Explicitly out of scope:

- waveform rendering
- scrubbing or seeking
- background playback
- app-wide shared playback controls
- playlist or queue behavior

## Recommended Approach

Introduce a small playback abstraction dedicated to meeting recordings rather than placing `AVAudioPlayer` directly inside the SwiftUI view or expanding `AppViewModel` into a global audio controller.

This keeps playback concerns local to the meeting detail experience while still separating file loading, native player integration, and error handling from the view layer. It also gives us a narrow seam for tests.

## Design

### Playback boundary

Add a lightweight `MeetingAudioPlayer` interface that supports:

- loading a meeting recording from a file path or file URL
- toggling between play and pause
- exposing whether playback is idle, ready, playing, paused, or failed

The concrete implementation will wrap `AVAudioPlayer`.

### UI integration

Update `MeetingDetailView` to include an "Audio Playback" section for the selected meeting.

The section will show:

- a play or pause button
- a short status label such as "Ready", "Playing", "Paused", or an error message
- the existing saved audio file path

The detail view will prepare the player when it appears or when the selected meeting changes. If the file does not exist or cannot be decoded, the play button will stay disabled and the status will explain the issue.

### Lifecycle and behavior

The player is scoped to the detail view rather than shared app-wide.

Expected behavior:

- selecting a recorded meeting prepares that meeting's audio file
- pressing Play starts playback
- pressing Pause pauses playback
- switching to a different meeting stops the current playback and prepares the next recording
- selecting a meeting whose recording is unavailable shows a non-crashing error state

## Error Handling

Handle these cases explicitly:

- file path does not exist
- file path points to an unreadable or unsupported file
- native player initialization fails

Errors should be surfaced as user-readable status text in the detail screen, not thrown into app-level state.

## Testing

Follow test-first development for the new behavior.

Tests should cover:

- loading a valid meeting recording moves the player into a ready state
- toggling play and pause updates observable playback state
- loading a missing file produces a failed state with a user-facing message
- loading a new meeting while one is active resets playback for the new selection

UI assertions should stay light. Most behavior should be verified through the playback abstraction and its state transitions.

## Risks and Mitigations

Risk:
`AVAudioPlayer` callbacks may not align cleanly with SwiftUI state updates.

Mitigation:
Keep the wrapper small and observable, and centralize native delegate handling in the playback implementation instead of the view.

Risk:
Preview or test environments may not have real audio assets.

Mitigation:
Use a test double for player behavior where possible and limit native audio coverage to the thin integration layer.
