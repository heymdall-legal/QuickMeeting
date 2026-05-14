# Multi-App Auto-Recording Design

## Goal

Replace the current single hardcoded watched-app setting with a user-managed list of native macOS apps selected from the filesystem. The app should extract each selected app's bundle identifier automatically and use those bundle identifiers for auto-recording detection. Recording logic should remain generic: start recording only when the microphone is active and at least one selected app is running with visible or recent foreground activity, then stop after the existing grace period once no selected app still qualifies.

## Scope

- Replace the single selected app model with a persisted watched-app list.
- Let the user add apps from a file picker pointed at `.app` bundles.
- Extract bundle identifier and display metadata from the selected bundle automatically.
- Deduplicate watched apps by bundle identifier.
- Let the user remove watched apps from Settings.
- Keep the existing generic detection rule and coordinator timing behavior.
- Update monitoring so presence becomes active when any watched app qualifies.
- Add test coverage for watched-app persistence, selection validation, deduplication, removal, and multi-app monitoring behavior.

## Non-Goals

- No app-specific detection or recording logic per selected app.
- No reverse-engineered or private integration with meeting apps.
- No browser-tab detection.
- No icon management, app-health badges, or path-revalidation UI in v1.
- No automatic disabling of auto-recording when the watched-app list becomes empty.

## Approaches Considered

### Recommended: Persist lightweight watched-app records

Store each selected app as a lightweight record containing `bundleIdentifier`, `displayName`, and `appPath`. The runtime uses only bundle identifiers for detection, while the UI uses display metadata to show the list clearly. This keeps detection simple and stable while supporting the Finder-driven selection flow.

### Persist only bundle identifiers

Store only `[String]` bundle identifiers and reconstruct display information later when needed. This keeps persistence minimal, but it produces a weaker Settings experience and makes the UI dependent on later app discovery.

### Rich per-app state model

Store bundle identifier, path, display name, icon, and ongoing validity state for each app. This would support richer diagnostics, but it adds complexity that is not needed for the first version.

## Architecture

Replace the current `AutoRecordingApp` enum and single `selectedApp` field with a lightweight persisted model such as `AutoRecordingTarget`.

Responsibilities:

- `AutoRecordingTarget`
  - Represents one watched app selected by the user.
  - Stores `bundleIdentifier`, `displayName`, and `appPath`.
- `AutoRecordingSettings`
  - Replaces `selectedApp` with `selectedApps: [AutoRecordingTarget]`.
  - Continues to store the enabled flag and timing values.
- `AutoRecordingSettingsStore`
  - Persists the watched-app list alongside the existing timing settings.
  - Normalizes stored targets so bundle identifiers remain unique.
- `AutoRecordingSettingsViewModel`
  - Loads and saves the watched-app list.
  - Adds actions to import an app bundle, validate it, dedupe it, and remove it.
  - Owns simple user-facing error state for invalid selections.
- `AutoRecordingSettingsSections`
  - Replaces the single-app picker with a managed watched-app list UI.
  - Presents add and remove controls plus the existing delay sliders.
- `MeetingAppActivitySource`
  - Stops depending on a hardcoded enum-to-bundle-ID mapping.
  - Samples activity for a provided bundle identifier or target.
- `MeetingAppMonitor`
  - Polls the current watched-app list.
  - Evaluates presence as active when any selected app qualifies.
  - Resets detector state when auto-recording becomes disabled or when the watched-app list becomes empty.
- `MeetingPresenceDetector`
  - Remains generic and unchanged in purpose.
  - Still evaluates a single sample using microphone activity plus running, visible-window, and recent-focus signals.
- `AutoRecordingCoordinator`
  - Remains unchanged in behavior.
  - Continues to apply the start delay and stop grace period once presence states are emitted.

This keeps the runtime path generic. App selection becomes data, while detection continues to operate on bundle identifiers without branching by app type.

## Data Model

`AutoRecordingTarget` should be a small `Codable`, `Equatable`, and `Sendable` value with:

- `bundleIdentifier: String`
- `displayName: String`
- `appPath: String`

`AutoRecordingSettings` should change from:

- `selectedApp: AutoRecordingApp`

to:

- `selectedApps: [AutoRecordingTarget]`

Bundle identifier is the source of truth for runtime detection. The stored path exists only to preserve what the user selected and to support understandable Settings UI. Duplicate bundle identifiers are not allowed; adding an app whose bundle identifier already exists in the list is a no-op.

## Selection Flow

1. The user opens Settings and clicks `Add App...`.
2. The app presents a file picker restricted to application bundles.
3. The user selects a `.app`.
4. The view model reads the bundle from disk.
5. The app extracts:
   - bundle identifier
   - display name
   - selected path
6. Validation rules:
   - the selected item must be a valid app bundle
   - the bundle must expose a bundle identifier
7. If validation fails, the app shows a simple error and does not modify the list.
8. If the bundle identifier is already present in the watched list, the operation is a no-op.
9. Otherwise, the app appends a new watched target and saves settings immediately.

## Detection Flow

1. `MeetingAppMonitor` loads the latest auto-recording settings during polling.
2. If auto-recording is disabled, the detector resets and the app reports `.inactive`.
3. If the watched-app list is empty, the detector also resets and the app reports `.inactive`.
4. Otherwise, the monitor samples activity for each watched app's bundle identifier.
5. The monitor determines whether any sample qualifies for active meeting detection.
6. If one or more apps qualify, the monitor feeds one qualifying sample into the existing detector path.
7. If no watched app qualifies, the monitor reports inactive behavior through the existing detector and coordinator path.
8. `AutoRecordingCoordinator` still applies the configured start delay and stop grace period before requesting start or stop.

The qualification rule stays simple and shared across all watched apps:

- microphone must be active
- app must be running
- app must have a visible window or recent focus

No per-app recording behavior is introduced. The monitor only answers whether at least one selected app currently satisfies the existing heuristic.
Detector stability should be interpreted across overall watched-app activity, not pinned to one specific app remaining active across all samples.

## Settings UX

Replace the current `Watched app` picker with a small managed list in the auto-recording section.

The section should provide:

- `Enable auto recording` toggle
- `Add App...` action
- watched-app list showing each app's display name
- remove control for each watched app
- existing start-delay slider
- existing stop-grace slider

Recommended helper text:

`Recording starts when the microphone is active and any selected app is in use.`

Expected interaction behavior:

- adding an already-watched app makes no visible change
- removing an app updates settings immediately
- removing the final app leaves auto-recording enabled but effectively inactive until another app is added

## Error Handling

Invalid selection should fail clearly and locally.

Cases to handle:

- selected item is not a valid app bundle
- selected app bundle has no bundle identifier
- app metadata cannot be read from disk

In each case:

- show a simple Settings error message
- keep the existing watched-app list unchanged
- do not change auto-recording enabled state

If the watched-app list is empty at runtime, auto-recording should quietly remain inactive rather than creating partial state or disabling itself automatically.

## Testing

Add or update automated tests for:

- `AutoRecordingSettingsStore` round-tripping multiple watched apps
- watched-app deduplication by bundle identifier
- removal from the watched-app list
- invalid app selection rejection
- missing bundle identifier rejection
- `AutoRecordingSettingsViewModel` load and save behavior for watched apps
- `MeetingAppMonitor` reporting active presence when any watched app qualifies
- `MeetingAppMonitor` reporting inactive presence when no watched apps qualify
- preservation of existing detector and coordinator behavior once a qualifying sample exists

Testing emphasis should stay on the new list-management logic and the monitor's `any watched app qualifies` aggregation behavior. The detector and coordinator do not need redesign; they only need regression protection where the multi-app monitor now feeds them.

## Risks And Mitigations

- Path drift after selection:
  The stored path may become stale if the user moves the app later. Runtime detection is protected because bundle identifier remains the source of truth.
- Duplicate app installs sharing a bundle identifier:
  The app deduplicates on bundle identifier, so repeated selections are harmless no-ops.
- Empty watched list confusion:
  The Settings copy should make the rule clear, and runtime behavior should remain safely inactive.
- Overcomplicating detection:
  The design keeps app-specific logic out of recording decisions and limits the change to selection, persistence, and aggregation.

## Implementation Notes

- Prefer to introduce a small reusable helper for reading app-bundle metadata from a selected `.app` URL so bundle parsing stays testable.
- Keep persistence backward-safe by treating missing stored watched-app data as an empty list for new installs and migrating existing single-app `Толк` configurations into a one-item watched-app list when legacy settings are present.
- Ensure any current code that assumes a single `selectedApp` is updated to use the watched-app list explicitly rather than recreating hidden single-app assumptions.
