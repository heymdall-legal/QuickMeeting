# Menubar Status Icon Design

## Summary

QuickMeeting should reflect its current recording readiness directly in the macOS menubar icon. The default icon should remain unchanged while the app is idle. When auto-recording has detected a qualifying meeting app and is waiting out the start delay, the menubar icon should show a subtle badge indicating that recording will begin soon. When QuickMeeting is actively recording, the menubar icon should show a stronger static badge so the active state is unmistakable at a glance.

This design keeps the existing menu bar architecture and auto-recording pipeline intact. It adds a small derived icon-state layer and a deterministic image builder so the visual state is driven by explicit app state rather than UI copy.

## Goals

- Preserve the current QuickMeeting icon identity while idle
- Show a clear visual distinction between "recording soon" and "recording now"
- Reuse existing app state instead of introducing a parallel status system
- Keep the icon logic deterministic and unit-testable
- Avoid animation so the menubar item stays calm in peripheral vision

## Non-Goals

- Redesigning the menu bar popover layout or commands
- Adding animated menubar effects
- Introducing new auto-recording business logic or timing behavior
- Adding extra icon states for stop grace, failures, or transcription

## Current State

`MenuBarController` creates an `NSStatusItem` and sets a fixed `waveform.circle` symbol as the button image. The menu bar popover already displays recording text and optional auto-recording text through `MenuBarView`.

`AppViewModel` already exposes the key status signals:

- `recordingState`
- `autoRecordingStatusText`

The current limitation is that the icon itself is static, so users need to open the menu or watch the main window to know whether QuickMeeting is about to auto-start or is already recording.

## Desired Behavior

QuickMeeting should present exactly three menubar icon states:

1. `idle`
2. `pendingAutoRecord`
3. `recording`

The behavior should be:

- `idle`: show the current base icon with no badge
- `pendingAutoRecord`: show the base icon with a subtle static badge
- `recording`: show the base icon with a stronger static badge

State priority should be:

1. `recording` wins whenever the app is actively recording
2. `pendingAutoRecord` is shown only while auto-recording is in the pre-start delay window
3. all other situations fall back to `idle`

This means stop grace, generic failures, and unrelated auto-recording text should not imply that recording is imminent.

## Proposed Architecture

### 1. `MenuBarIconState`

Add a focused enum that represents only what the menubar icon needs to know:

```swift
enum MenuBarIconState: Equatable {
    case idle
    case pendingAutoRecord
    case recording
}
```

This should be derived from existing app state rather than stored independently.

### 2. Derived state in `AppViewModel`

Expose a derived property from `AppViewModel` for the menu bar icon state. The key design point is that the menu bar should not infer behavior from display strings. Instead, `AppViewModel` should surface a dedicated semantic signal for "auto-recording start is pending," and then map:

- active `recordingState` -> `.recording`
- pending auto-record start -> `.pendingAutoRecord`
- otherwise -> `.idle`

This keeps image selection independent from English text and lets the UI evolve without breaking status logic.

### 3. `MenuBarController` update flow

`MenuBarController` should remain the owner of the `NSStatusItem` and popover. It should also observe the view model's derived icon state and update the status item image whenever that state changes.

Responsibilities:

- subscribe to view-model changes
- compute the current icon image from `MenuBarIconState`
- apply the image to `statusItem.button`

The controller should not own detection rules or special-case business logic.

### 4. `MenuBarIconImageBuilder`

Add a small helper responsible for generating the image for each icon state from the same base symbol.

Responsibilities:

- render the base symbol for idle
- render a subtle badge variant for pending auto-record
- render a stronger badge variant for recording

Keeping this separate avoids packing image construction into `MenuBarController` and gives us one place to tune sizing, placement, and symbol configuration later.

## Visual Design

### Base identity

Keep the current `waveform.circle` symbol as the base identity for all states. The icon should feel like one persistent QuickMeeting symbol rather than three unrelated symbols.

### Pending auto-record

Use the base symbol plus a small, light badge in one corner. The badge should read as "armed" or "queued" rather than urgent. It should be visible, but intentionally quieter than the recording state.

### Recording

Use the same base symbol plus a more prominent filled badge in the same corner. The stronger shape and accent should make active recording easy to distinguish from pending auto-record at a glance.

### Color behavior

The design should use both shape and subtle color where supported. Shape carries the meaning first so the icon still works in template-style contexts. Color is secondary reinforcement, not the only signal.

### Motion

Both active states should remain static. No pulsing, bouncing, or frame-based animation should be introduced.

## State Mapping Rules

The menu bar icon should not be derived from `autoRecordingStatusText`. That string is presentation copy and can drift from behavior over time.

Instead, QuickMeeting should expose a semantic pending-start signal based on the auto-recording coordinator lifecycle. The icon should map state with the following rules:

- if `recordingState` is `.recording` or `.stopping`, show `.recording`
- else if an auto-recording start has been scheduled but not yet fired, show `.pendingAutoRecord`
- else show `.idle`

Treating `.stopping` as recording keeps the icon from flickering back to idle during the stop handoff.

## Integration Details

The existing architecture is already close to what we need:

- `MeetingAppMonitor` detects meeting presence
- `AutoRecordingCoordinator` schedules delayed start and stop intents
- `AppViewModel` is already the integration point between auto-recording and UI
- `MenuBarController` already owns the status item

The integration change is to make pending auto-record an explicit view-model-visible state. The cleanest boundary is for the coordinator and intent sink flow to expose whether a delayed auto-start is currently armed, without changing any recording timing behavior.

## Error Handling

Failures should fall back to `idle` unless the app is still actively recording or stopping. This avoids overstating confidence and prevents the icon from looking "armed" after an auto-recording attempt has already failed or been canceled.

If the pending auto-record flag and the actual recording state temporarily disagree, `recording` should always win.

## Testing Strategy

### Unit tests for state mapping

Add focused tests around the derived icon-state mapping to verify:

- idle recording state with no pending auto-record -> `.idle`
- pending auto-record without recording -> `.pendingAutoRecord`
- active recording -> `.recording`
- stopping recording -> `.recording`
- recording takes precedence over pending auto-record

These tests should not depend on AppKit.

### Lightweight image builder tests

Add narrow tests that verify the image builder can produce non-nil images for each icon state and that state selection is deterministic. We do not need pixel-perfect snapshot tests for the first implementation.

### Manual verification

Manually verify the menubar icon in three situations:

1. app idle
2. auto-recording has detected a target app and is waiting to start
3. active recording is in progress

## Implementation Notes

- Follow the current menu bar structure instead of introducing a separate menubar view model
- Prefer a small helper or extension for icon construction rather than embedding drawing logic inline
- Keep the state enum and mapping narrow so future icon additions stay intentional

## Open Decisions Resolved

The following product decisions are fixed by this design:

- idle keeps the current QuickMeeting icon
- "recording soon" uses a badge, not a full symbol swap
- recording uses a stronger badge than pending auto-record
- both active states remain static
- color is used as secondary reinforcement, not the primary signal

## Out of Scope Follow-Ups

Possible future enhancements, intentionally excluded from this implementation:

- adding a dedicated failure icon treatment
- showing transcription progress in the menubar icon
- animating the recording state
- replacing composited symbols with handcrafted menubar assets if visual polish later requires it
