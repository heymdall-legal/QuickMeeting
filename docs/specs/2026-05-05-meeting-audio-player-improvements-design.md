# Meeting Audio Player Improvements Design

## Goal

Improve the meeting detail audio player so playback progress is visible, playback completion returns the UI to a non-playing state, and the user can jump to a different playback position.

## Scope

Included in this change:

- visible playback progress in the meeting detail view
- elapsed and total time display for the current recording
- seeking to a new playback position from the detail view
- resetting playback state and playhead when playback reaches the end
- automated tests for progress, completion, and seeking behavior

Explicitly out of scope:

- waveform rendering
- background playback
- app-wide shared playback controls
- playlist or queue behavior
- transcript-synced playback

## Recommended Approach

Extend the existing `MeetingAudioPlayback` model into a small time-aware playback controller instead of moving playback logic into the SwiftUI view or introducing a broader shared audio subsystem.

This keeps the logic local to the meeting detail experience, preserves a clean seam around `AVAudioPlayer`, and lets us test playback state transitions without relying on UI-driven polling.

## Design

### Playback boundary

Expand the playback abstraction so it can expose:

- current playback state: `idle`, `ready`, `playing`, `paused`, or `failed`
- `currentTime` for the active recording
- `duration` for the loaded recording
- a seek API that moves playback to a requested time within the valid range
- a completion callback path from the native player wrapper back into the observable model

The concrete adapter will continue to wrap `AVAudioPlayer`, but the protocol surface will grow to support reading and setting playback time and reporting playback completion.

### Progress updates

`MeetingAudioPlayback` will own the progress model rather than the view.

When playback starts, the model will begin a lightweight repeating update mechanism that refreshes `currentTime` from the native player. When playback pauses, stops, reloads, or finishes, the updates stop. This keeps the SwiftUI view simple and ensures the same state transitions are used by both button taps and end-of-playback events.

Completion behavior:

- when audio reaches the end, playback state returns to `ready`
- `currentTime` resets to `0`
- the progress UI returns to the start position
- the play button returns to its non-playing appearance

### UI integration

Update `MeetingDetailView` to expand the existing "Audio Playback" section with:

- the existing play or pause button
- a scrubber bound to the playback model
- elapsed and total duration labels
- the existing status label

The scrubber should be enabled only when playback is available. Dragging or clicking the scrubber seeks immediately. If playback is already active, audio should continue from the new position; if playback is paused or ready, only the position changes.

### Lifecycle and behavior

Expected behavior:

- loading a meeting recording prepares the player and publishes its duration
- pressing Play starts playback and progress updates
- pressing Pause pauses playback and freezes the displayed progress
- seeking changes the playhead to the chosen time
- switching to a different meeting stops existing playback, resets progress updates, and prepares the new recording
- selecting a meeting whose recording is unavailable still shows a friendly failure state without crashing

## Error Handling

Handle these cases explicitly:

- file path does not exist
- file path points to an unreadable or unsupported file
- seek requests arrive when no recording is loaded
- seek requests overshoot the valid playback range

The model should clamp out-of-range seek values into the valid `0...duration` range and ignore playback actions that are invalid for the current state. Errors should continue to surface as user-readable status text in the detail screen rather than escaping into app-level state.

## Testing

Follow test-first development for the new behavior.

Tests should cover:

- loading a valid recording publishes a ready state with a non-zero duration
- toggling play begins playback and progress publication
- pausing stops playback without clearing the current position
- native playback completion returns state to `ready` and resets position to `0`
- seeking updates the native player time and observable progress
- loading a new recording while one is active resets previous playback state cleanly

UI assertions should stay light. Most behavior should be verified through `MeetingAudioPlayback` and a native player test double that can simulate elapsed time and completion.

## Risks and Mitigations

Risk:
Progress updates driven by a timer can drift or continue running after playback stops.

Mitigation:
Start updates only while state is `playing`, stop them on every exit path from active playback, and verify that completion and reload paths both tear the updater down.

Risk:
Seeking and playback completion can race, leaving the UI in an inconsistent state.

Mitigation:
Centralize all playback-state changes inside `MeetingAudioPlayback` on the main actor and keep the native adapter callback narrow and deterministic.
