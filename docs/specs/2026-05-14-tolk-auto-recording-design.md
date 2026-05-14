# Tolk Auto-Recording Design

## Goal

Add an auto-recording mode that watches the native macOS `Толк` app, detects when the user appears to be in an actual meeting, starts recording automatically after a short confirmation window, and stops recording automatically after meeting activity disappears for a grace period.

## Scope

- Add a user-facing auto-recording setting that can be enabled or disabled.
- Add a watched app selection model, with `Толк` as the first supported profile.
- Detect likely live meeting activity for the selected app using system-level activity heuristics.
- Wait 10 seconds of stable qualifying activity before auto-starting recording.
- Wait through a configurable stop grace period before auto-stopping recording.
- Reuse the existing manual recording flow so auto-recording enters the same meeting creation and capture pipeline.
- Surface auto-recording status in the UI so the behavior is visible and explainable.
- Add test coverage for detector state transitions and coordinator timing logic.

## Non-Goals

- No network-traffic-based meeting detection.
- No browser-tab detection.
- No attempt to support every meeting app in the first iteration.
- No app-specific deep integration with `Толк` private APIs or reverse-engineered protocols.
- No silent background creation and cleanup of meeting records from weak candidate detections.
- No replacement of manual recording controls; manual start and stop continue to work.

## Approaches Considered

### Recommended: `Толк`-specific detector built on a generic detector architecture

Use a generic monitoring boundary in the app, but make the first concrete implementation specifically tuned for the native `Толк` app using system-visible activity signals. This gives the best chance of useful accuracy for the real target while keeping room for future app profiles.

### Generic detector for any selected native app

Build one heuristic detector with no app-specific tuning. This is more reusable on paper, but it is more likely to be noisy because different apps expose different process, window, and media-usage behavior.

### Network-activity detector

Infer meeting presence from sockets, connections, or traffic patterns. This is not recommended because it is fragile, likely needs heavier privileges, and is harder to explain and validate than process-level and activity-level heuristics.

## Architecture

Add a new auto-recording extension layer around the existing recording flow.

Responsibilities:

- `RecordingService`
  - Remains responsible only for starting and stopping audio capture.
- `AppViewModel`
  - Remains the single owner of recording lifecycle decisions inside the app layer.
  - Accepts auto-recording start and stop requests through the same paths already used by manual controls.
- `MeetingAppMonitor`
  - Owns periodic monitoring of the selected app profile.
  - Emits app-owned presence states rather than raw OS details.
- `MeetingPresenceDetector`
  - Evaluates sampled system activity signals for one supported app profile.
  - Produces confidence-oriented presence states such as `inactive`, `candidateActive`, `activeMeeting`, and `ending`.
- `AutoRecordingCoordinator`
  - Consumes presence changes.
  - Applies the 10-second start confirmation window and stop grace period.
  - Prevents duplicate or conflicting auto-start and auto-stop actions.
- `AutoRecordingSettingsStore`
  - Persists whether auto-recording is enabled, which app profile is selected, and the timing values.

`QuickMeetingApp` wires the monitor, detector, settings store, and coordinator once and passes them into the app layer alongside the existing recording and calendar services.

## Detection Model

The detector should not rely on a single binary API. Instead, it should derive confidence from a combination of system-visible signals for the native `Толк` process.

Candidate signals for v1:

- `processRunning`
  - The `Толк` app process is currently running.
- `recentlyForegrounded`
  - `Толк` is frontmost now or was frontmost recently enough to count as active use.
- `mediaUsage`
  - macOS indicates microphone and/or camera usage attributable to the app, if available through supported APIs.
- `windowPresence`
  - The app has a visible window, which helps distinguish an installed background process from a user-facing session.
- `stabilityOverTime`
  - The qualifying combination persists across multiple polling intervals.

The detector should combine these into app-owned states:

- `inactive`
  - Not enough evidence of a live meeting.
- `candidateActive`
  - Some evidence exists, but not enough to start recording yet.
- `activeMeeting`
  - Evidence is strong enough and stable enough to treat the app as being in a live meeting.
- `ending`
  - Evidence fell below threshold while a recording is active, but the stop grace period has not expired yet.

If a stronger signal such as app-attributed media usage is not available for `Толк`, the detector should continue to function with reduced confidence using process, window, and recent-activity signals rather than failing completely.

## Data Flow

1. The user enables auto-recording for `Толк` in Settings.
2. `MeetingAppMonitor` begins polling the native app activity source on a short interval.
3. `MeetingPresenceDetector` evaluates the sampled signals and emits the current presence state.
4. `AutoRecordingCoordinator` receives the state changes.
5. When the detector enters a qualifying candidate state, the coordinator starts a 10-second confirmation window.
6. If the qualifying state remains stable for the full window, the coordinator requests recording start through the same app-owned path as manual recording.
7. While recording is active, the monitor continues evaluating presence.
8. When meeting evidence disappears, the coordinator enters a stop grace period rather than stopping immediately.
9. If meeting evidence returns before grace expires, the pending stop is canceled.
10. If evidence stays below threshold for the full grace period, the coordinator requests recording stop through the existing recording flow.

## Settings UX

Add a new Settings section for auto-recording.

The pane should allow the user to:

- enable or disable auto-recording
- select the watched app profile
- configure a start confirmation window, defaulting to 10 seconds
- configure a stop grace period, defaulting to 60 seconds

For the first iteration:

- `Толк` is the only supported profile exposed in the UI
- the architecture should still treat app selection as data so additional profiles can be added later without redesigning the feature

## Runtime UX

Auto-recording should be visible and understandable in the same UI shell that already exposes recording state.

Expected behavior:

- When `Толк` first appears meeting-like, the app shows a status such as `Detected meeting activity in Толк, waiting 10s`.
- If the signal remains stable, recording starts automatically using the existing recording flow.
- Once recording is active, the UI indicates that the current recording was auto-started.
- When meeting evidence disappears, the UI shows a pending-stop state such as `Meeting activity lost, stopping soon`.
- If evidence returns during the grace period, the pending stop is canceled and the UI returns to the normal recording state.

The feature should feel automatic but never invisible.

## Error Handling

- If required signal access is unavailable, the feature should disable itself gracefully and explain that detection could not be initialized.
- If recording permissions are denied when an auto-start is attempted, the app should surface the same failure state used by manual recording.
- If detector signals are noisy, the coordinator should prefer inaction over repeated start-stop thrashing.
- If the app cannot reach the confidence threshold, no meeting record should be created.
- If auto-stop fails, the recording should remain recoverable through the existing failure path.
- Detector state transitions should be logged for diagnostics so the heuristic can be tuned with real `Толк` behavior later.

## Testing

Add automated tests for:

- detector transitions from `inactive` to `candidateActive` to `activeMeeting`
- stable qualifying samples being required before auto-start
- auto-start being skipped when a manual recording is already active
- stop grace beginning only after qualifying evidence disappears
- pending stop cancellation when evidence returns before grace expiry
- auto-stop after the full grace period elapses
- noisy signal sequences not causing repeated start-stop thrash
- disabled auto-recording mode ignoring detector events

Testing structure:

- use protocol-backed native activity sources so `Толк` signals can be simulated in tests
- keep most logic coverage at the detector and coordinator layers
- use a smaller amount of `AppViewModel` coverage to confirm auto-recording actions reuse the existing recording path correctly

Manual validation remains part of the design because the biggest technical risk is the quality of system-visible signals for the real `Толк` app.

## Future Extensions

- Add more native app profiles beyond `Толк`.
- Split app-specific signal rules into separate detector strategies behind the same boundary.
- Blend detector confidence with calendar context later if a lower-false-positive mode is needed.
- Add richer status reporting or diagnostics if users need help tuning the feature.
