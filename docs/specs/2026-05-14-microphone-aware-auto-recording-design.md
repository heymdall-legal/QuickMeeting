# Microphone-Aware Auto Recording Design

## Summary

QuickMeeting's automatic meeting detection should treat microphone activity as the primary trigger for meeting presence, but only in combination with evidence that the selected meeting app is the app currently involved. The intended behavior is:

- microphone activity is required
- if the microphone is inactive, QuickMeeting ignores all other signals
- if the microphone is active, the selected app must also be running
- if the microphone is active and the selected app is running, either a visible window or recent focus within the last 30 seconds qualifies the app as active for meeting detection

This design keeps the existing auto-recording monitor and coordinator structure, while adding a dedicated microphone activity source and making app focus recency an explicit, time-based signal.

## Goals

- Make microphone activity a must-have signal for automatic meeting detection
- Reduce false positives from unrelated app focus or visible windows
- Preserve the current start delay and stop grace behavior
- Keep the design reusable for future supported meeting apps beyond Tolk
- Keep detection logic testable without real CoreAudio devices

## Non-Goals

- Determining which exact process owns the microphone at the OS level
- Adding app-specific reverse engineering of Tolk internals
- Changing recording pipeline behavior or permissions flow
- Adding Bluetooth-specific fallback behavior in the first implementation

## Current State

Today, `NativeMeetingAppActivitySource` builds a `MeetingAppActivitySample` from coarse app state:

- whether the selected app is running
- whether it is frontmost
- whether it has a visible window
- whether it had recent focus
- whether it is using media

In practice, `isUsingMedia` is always hardcoded to `false`, so the detector currently depends on running, visibility, and focus signals only. That means microphone activity does not influence automatic recording at all.

## Desired Behavior

QuickMeeting should only detect an active meeting when all of the following are true:

1. Some microphone input device is currently active
2. The selected meeting app is running
3. The selected meeting app either:
   - has a visible window, or
   - was frontmost within the last 30 seconds

If microphone activity stops, the meeting should stop qualifying immediately at the detection layer. The existing auto-recording stop grace period should still govern when recording actually stops.

## Proposed Architecture

### 1. `MicrophoneActivitySource`

Add a new protocol dedicated to microphone activity:

- responsibility: answer whether any microphone input device is active
- scope: global machine-level microphone state
- no knowledge of meeting apps or recording decisions

Proposed shape:

```swift
protocol MicrophoneActivitySource: Sendable {
    func isMicrophoneActive() -> Bool
}
```

The protocol stays intentionally small so the implementation can evolve from polling to event-backed caching without affecting the rest of the auto-recording code.

### 2. `NativeMicrophoneActivitySource`

Add a native implementation backed by CoreAudio device state, modeled after BeezyLight's approach.

Responsibilities:

- enumerate audio input devices
- observe device list changes
- observe `kAudioDevicePropertyDeviceIsRunningSomewhere` changes for input devices
- maintain cached microphone-active state
- expose a synchronous `isMicrophoneActive()` read for the polling monitor

This source should own CoreAudio-specific complexity so the app activity source and presence detector remain simple.

### 3. `NativeMeetingAppActivitySource`

Extend the existing native activity source so it combines:

- app running state
- frontmost state
- visible window state
- recent focus state derived from timestamps
- microphone activity from `MicrophoneActivitySource`

This type should track a per-selected-app `lastFocusedAt` timestamp and compute `hadRecentFocus` by comparing that timestamp to the current time using a configurable focus recency window, defaulting to 30 seconds.

### 4. `MeetingAppActivitySample`

Update the sample model to represent the new primary signal explicitly. The existing `isUsingMedia` field should be replaced with a microphone-focused field, for example:

```swift
struct MeetingAppActivitySample: Equatable, Sendable {
    let bundleIdentifier: String
    let isRunning: Bool
    let isFrontmost: Bool
    let hadRecentFocus: Bool
    let hasVisibleWindow: Bool
    let isMicrophoneActive: Bool
}
```

This keeps the model aligned with actual detection behavior rather than a vague media concept.

### 5. `MeetingPresenceDetector`

Keep the detector as a pure rule evaluator with no OS knowledge and no time tracking.

Updated qualification rule:

```swift
qualifies =
    sample.isMicrophoneActive
    && sample.isRunning
    && (sample.hasVisibleWindow || sample.hadRecentFocus)
```

The existing stable sample promotion remains useful:

- first stable qualifying samples become `.candidateActive`
- after the configured stable sample count, presence becomes `.activeMeeting`
- any non-qualifying sample resets the stable count and returns `.inactive`

## CoreAudio Detection Strategy

The native microphone source should follow the same high-level mechanism as BeezyLight:

- enumerate CoreAudio devices
- filter to devices that support input
- for each input device, inspect `kAudioDevicePropertyDeviceIsRunningSomewhere`
- listen for property changes so cached state stays fresh

This is appropriate for QuickMeeting because it provides a low-level signal for whether macOS currently has an input device running, without having to capture or inspect microphone audio.

### Why this approach fits QuickMeeting

- It is lightweight and separate from the recording pipeline
- It does not require starting audio capture just to detect meetings
- It can be layered into the existing polling monitor with minimal structural change
- It matches the intended product behavior where mic activity is necessary but not sufficient

### Deferred behavior: Bluetooth fallback

BeezyLight includes a fallback for Bluetooth devices by checking the macOS orange microphone indicator because some Bluetooth devices reportedly return false negatives for `isRunningSomewhere`.

This design intentionally defers that fallback for the initial QuickMeeting implementation because:

- it relies on system UI inspection rather than a clear documented ownership signal
- it is more brittle than the CoreAudio property path
- it should only be added if real QuickMeeting testing shows Bluetooth false negatives

If later testing shows a meaningful Bluetooth gap, that fallback can be added as a follow-up behind the same `MicrophoneActivitySource` abstraction.

## App-Side Signal Strategy

Microphone activity is global and does not tell QuickMeeting which app is using it. To avoid false positives, QuickMeeting should require selected-app evidence in addition to mic activity.

The app-side evidence rules are:

- `isRunning` is required
- `hasVisibleWindow` counts as active evidence
- `hadRecentFocus` counts as active evidence for 30 seconds after the selected app was frontmost

`isFrontmost` should still be collected, but only as an input used to refresh `lastFocusedAt`. It does not need to be part of the final detector rule once `hadRecentFocus` exists.

## Focus Recency Model

The native app activity source should maintain:

- `lastFocusedBundleIdentifier`
- `lastFocusedAt`
- a configurable `recentFocusWindow`, default `30`

Behavior:

- when the selected app is frontmost during sampling, update `lastFocusedAt = now`
- if the selected app is no longer frontmost, treat `hadRecentFocus` as true while `now - lastFocusedAt <= 30s`
- when the selected app changes in settings, clear any focus history tied to the previous app

This makes detection resilient when the user tabs away from the call window during a meeting.

## Monitor Integration

`MeetingAppMonitor` can keep its current polling loop and reset behavior. The integration changes are:

- use the richer sample from `MeetingAppActivitySource`
- pass it into the updated detector
- preserve the current selected-app reset behavior

No changes are required to:

- `AutoRecordingCoordinator`
- start delay scheduling
- stop grace scheduling
- recording start/stop intent flow

## Failure Handling

If microphone state cannot be read, the system should fail closed:

- treat the sample as `isMicrophoneActive == false`
- do not infer meetings from app visibility or focus alone
- log the failure for diagnosis

This is safer than risking unwanted recordings.

Potential failure scenarios:

- CoreAudio device enumeration fails
- device property listener registration fails
- device list changes invalidate cached listeners

The microphone source should recover opportunistically by refreshing device state on the next change or poll-triggered read where practical, but the externally visible behavior remains conservative.

## Testing Strategy

### Unit tests for `MeetingPresenceDetector`

Add or update tests covering:

- mic inactive always returns `.inactive`
- mic active plus running plus visible window yields candidate then active
- mic active plus running plus recent focus yields candidate then active
- mic active plus running plus no visible window plus stale focus returns `.inactive`
- non-qualifying samples reset stable sample count

### Unit tests for `NativeMeetingAppActivitySource`

Introduce dependency seams so tests can control:

- current running apps
- current frontmost app
- current time
- visible-window detection
- microphone activity source result

Test cases:

- frontmost selected app refreshes `lastFocusedAt`
- recent focus stays true within 30 seconds
- recent focus expires after 30 seconds
- switching selected app clears stale focus relevance
- inactive microphone produces `isMicrophoneActive == false` regardless of app state

### Unit tests for `NativeMicrophoneActivitySource`

Keep the CoreAudio wrapper testable through thin protocol seams or injected closures where necessary. The goal is not to exercise real CoreAudio in unit tests, but to verify:

- cached state updates when devices report active
- cached state becomes false when no devices report active
- device list refresh swaps tracked devices correctly
- failures resolve to inactive rather than active

### Integration tests

Existing monitor and coordinator tests should continue to verify:

- qualifying presence triggers delayed start
- loss of qualifying presence triggers delayed stop
- changing selected app resets detector state

## Implementation Notes

- Keep microphone detection separate from recording capture code
- Do not reuse `AudioCapturePipeline` as a meeting detector input
- Prefer lightweight adapters around CoreAudio rather than importing a large third-party audio wrapper wholesale
- If BeezyLight-inspired code is adapted, preserve license attribution where required

## Alternatives Considered

### App-only heuristics

Rejected because they are already insufficient and fail the core product requirement that microphone activity must be a must-have signal.

### Mic activity alone

Rejected because microphone usage is global and would create false positives from unrelated apps.

### App-specific deep Tolk detection

Rejected for the first implementation because it is more brittle, harder to generalize, and unnecessary to satisfy the current product behavior.

## Rollout and Validation

Manual validation should cover:

1. Tolk running with no microphone usage does not trigger recording
2. Tolk running with microphone usage and visible window triggers recording after the configured start delay
3. Tolk running with microphone usage and recent focus within 30 seconds triggers recording even after switching away
4. Tolk running with microphone usage but no visible window and stale focus does not trigger recording
5. Recording stops after microphone activity is lost and the configured stop grace period elapses
6. Non-Tolk microphone usage alone does not trigger recording when Tolk is the selected app

## Open Follow-Ups

- Evaluate whether Bluetooth microphone devices need an orange-indicator fallback in practice
- Consider exposing the recent-focus window as a setting only if real usage shows demand
- Consider whether visible-window detection needs to become app-specific as more meeting apps are added
