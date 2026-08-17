# Maximum meeting duration

## Goal

Ensure every recording ends automatically after a user-configured maximum
duration, even when meeting-app activity is not detected correctly.

## Behaviour

- The default maximum meeting duration is 3 hours.
- The setting is expressed and edited only in whole hours.
- It applies to all recordings, whether the user started them manually or
  auto-recording started them.
- A recording reaching the configured limit follows the existing normal stop
  path: capture stops, the meeting is finished with the current time, and the
  normal recorded state is restored.
- Changing the setting affects recordings started after the change. It does not
  reschedule a recording that is already in progress.
- Stopping a recording by any other path cancels the pending maximum-duration
  timer. A failed recording start also leaves no timer running.

## Interface

The Auto-recording section of Settings gains a stepper row named `Maximum
meeting duration`. It presents and persists an integral number of `hours`.
The existing start-delay and silence-stop settings remain unchanged.

## Implementation boundaries

- `AutoRecordingSettings` stores `maximumMeetingDurationHours` alongside the
  existing auto-recording preferences. Its default is `3`.
- `AutoRecordingSettingsStore` persists that integer in `UserDefaults`, with
  the default used when existing installations have no saved value.
- `AutoRecordingSettingsViewModel` exposes the value to Settings and saves it
  when it changes.
- `AppViewModel` owns the per-recording deadline because it is the shared
  lifecycle authority for both manual and automatic starts/stops. It schedules
  the deadline after a successful start and calls the existing `stopRecording()`
  method when it expires.
- The deadline scheduler is injected behind the existing scheduling abstraction
  so tests can advance a deterministic clock instead of waiting for hours.

## Error handling

The deadline invokes the same stop implementation as the user-facing Stop
button. If stopping fails, the existing recoverable-recording behaviour remains
in effect and the deadline is cleared, preventing repeated stop attempts.

## Testing

- Settings-store coverage verifies the default of 3 hours and a saved value
  round-trip.
- View-model coverage verifies loading and saving the hours value.
- Recording lifecycle coverage verifies that the configured deadline stops a
  successful manual recording, applies to an automatic recording as well, and
  is cancelled when the recording ends earlier.

## Scope

This change adds one maximum-duration safety limit. It does not change meeting
activity detection, start delays, silence grace periods, or the format of the
recording duration display.
