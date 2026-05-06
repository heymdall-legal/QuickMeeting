# App Shell UI Design

## Summary

QuickMeeting will move from a meeting-only split view to a unified app shell with a persistent left sidebar and a detail pane on the right.

The sidebar will contain:

- An untitled top group with `Home` and `Settings`
- A `History` section listing meetings

The detail pane will show:

- A dedicated `Home` screen with recording controls
- The current settings content
- The current meeting detail view for history items

This change keeps history behavior the same while making recording controls and settings first-class destinations in the main window.

## Goals

- Make `Home` the default app destination
- Keep users on `Home` while recording instead of auto-jumping into meeting history
- Move recording controls into a dedicated main-window screen
- Show settings content inside the main app shell
- Preserve current history and meeting detail behavior

## Non-Goals

- Redesigning meeting history rows
- Adding badges, counters, or status chips to the history list
- Changing meeting detail behavior or transcription flow
- Changing the menu bar app behavior
- Removing the standalone macOS Settings scene

## Information Architecture

The main window will use one `NavigationSplitView` as the top-level shell.

The left sidebar structure will be:

- Untitled group
- `Home`
- `Settings`
- `History`
- Meeting 1
- Meeting 2

The right pane will switch based on a unified sidebar selection model:

- `home`
- `settings`
- `meeting(UUID)`

The app will launch with `Home` selected.

## Navigation Behavior

- Selecting `Home` shows the recording control screen
- Selecting `Settings` shows the current settings content
- Selecting a meeting in `History` shows the current meeting detail view
- Starting or stopping a recording does not change sidebar selection automatically
- If a selected meeting is deleted or otherwise disappears from the query results, selection falls back to `Home`
- If history is empty, `Home` and `Settings` still work normally and `History` simply shows no meeting rows

## Home Screen

`Home` becomes the dedicated recording surface in the main window.

It will contain:

- Recording status text
- `Start Recording` button
- `Stop Recording` button

Behavior:

- The view reuses the existing `AppViewModel` recording actions
- Button enabled and disabled behavior continues to follow `canStartRecording` and `canStopRecording`
- Status text continues to reflect the current `recordingState`
- The main window toolbar recording controls will be removed to avoid duplicating the same actions in two places

The initial design should stay intentionally minimal. No additional dashboard content, meeting summaries, or recent activity blocks are included in this change.

## Settings Destination

The `Settings` destination inside the unified app shell will show the existing settings content directly.

Because the current settings flow only has one pane, the unified shell should render `ModelsSettingsView` in the main detail pane instead of embedding the current `SettingsView` split layout. This avoids nested split navigation and keeps the experience visually consistent with the rest of the app.

The standalone macOS Settings scene will remain available and continue to show `SettingsView(modelsViewModel:)` so the app still behaves normally when users open Settings from the system menu.

## History Destination

The `History` section remains functionally the same as the current app:

- Meeting rows stay flat
- Meeting row content stays the same
- Selecting a meeting shows the current `MeetingDetailView`
- No additional row polish, grouping, or metadata is added in this change

The only structural difference is that history becomes one section inside the broader unified sidebar rather than the entire sidebar.

## Component Design

### ContentView

`ContentView` will become the unified app shell and own the sidebar selection state.

Responsibilities:

- Hold the current sidebar selection
- Default selection to `Home`
- Render the sidebar and right-side detail pane
- Reconcile selection when meetings change
- Present existing deletion and transcription alerts

`ContentView` will need access to both:

- `AppViewModel`
- `ModelsSettingsViewModel`

### Sidebar View

Create a dedicated sidebar view responsible for rendering:

- The static destinations (`Home`, `Settings`)
- The `History` section
- The current meeting rows

This keeps sidebar layout and tagging logic out of `ContentView`.

### HomeView

Create a lightweight `HomeView` that is only responsible for:

- Showing recording status
- Triggering start recording
- Triggering stop recording

It should not own business logic beyond forwarding actions to `AppViewModel`.

### Reused Views

The following views should be reused with little or no behavioral change:

- `MeetingDetailView`
- `ModelsSettingsView`

`RecordingToolbarControls` will no longer be used by the main window after this redesign. It may remain in the codebase temporarily if still useful elsewhere, but the target end state for this feature is that the main window does not display those controls in its toolbar.

## State Handling

The prior meeting selection logic pinned the UI to the active or recoverable meeting while recording. That behavior should not carry over to the new shell.

New state rules:

- `Home` is the default selection on launch
- Recording state affects control availability and status text only
- Recording does not force the current selection to a meeting
- When a selected meeting becomes invalid, selection falls back to `Home`

This creates a cleaner separation between app navigation state and recording lifecycle state.

## Error Handling

No new error flows are introduced.

The unified shell will continue to present:

- Meeting deletion errors through the existing alert
- Transcription errors through the existing alert

Recording failure messaging continues to be surfaced through the `AppViewModel` recording state and displayed on the `Home` screen.

## Testing Strategy

Existing `AppViewModel` tests should remain valid because recording and meeting operations are not changing.

Add focused coverage for UI selection behavior where practical:

- Default selection resolves to `Home`
- Removing the selected meeting falls back to `Home`
- Recording does not overwrite a `Home` or `Settings` selection

Manual verification should cover:

- App launches with `Home` selected
- `Home` can start and stop recording
- Recording stays on `Home`
- `Settings` shows the current models settings UI
- `History` still opens meeting details correctly
- Deleting a selected meeting returns the detail area to `Home`

## Implementation Notes

- Prefer a small selection enum to represent sidebar destinations cleanly
- Preserve existing meeting query ordering
- Keep this change focused on app-shell composition; avoid unrelated refactors
- Follow existing SwiftUI patterns already used in the project unless a small extraction meaningfully improves clarity
