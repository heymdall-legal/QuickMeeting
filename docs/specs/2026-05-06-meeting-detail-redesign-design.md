# Meeting Detail Redesign

## Summary

QuickMeeting will redesign the meeting detail screen so the transcript becomes the primary content of the page. Metadata and meeting actions will move into a persistent right-hand inspector, and audio playback will become a docked control bar at the bottom of the view.

This change keeps the existing meeting selection, transcription flow, and playback behavior intact where possible while shifting the visual hierarchy toward a reading-first experience.

## Goals

- Make transcript content the primary focus of the meeting detail screen
- Move metadata and actions into a fixed right sidebar
- Keep audio playback visible in a docked bottom bar
- Show a simple empty state when no transcript exists
- Preserve existing transcription and deletion behavior

## Non-Goals

- Adding segmented transcript UI, timestamps, or speaker labels
- Changing meeting history navigation
- Redesigning meeting row appearance in the sidebar history list
- Changing transcription pipeline rules or audio playback internals
- Adding export, editing, or transcript annotation features

## Product Decisions

- The main content area shows a simple continuous transcript text view
- If no transcript exists, the main content area shows an empty state
- The `Transcribe` action appears both in the empty state and in the right sidebar
- The right sidebar is always visible
- The right sidebar is organized into sections, with `Details` before `Actions`
- The bottom player shows play or pause on the left, a progress bar in the middle, and a combined elapsed and total time display on the right

## Layout

The meeting detail screen will use a three-region layout:

- a primary transcript content area in the center
- a fixed-width inspector sidebar on the right
- a docked playback bar at the bottom

The center area should visually dominate the view and behave like a reading surface rather than a settings form. The right sidebar should remain secondary and should not compete with transcript content. The bottom playback bar should remain visible whether or not a transcript exists.

This should be implemented as a purpose-built layout for `MeetingDetailView` rather than a minor variation of the current vertically stacked scroll view.

## Main Content

### Transcript Present

When a transcript exists, the center content area should show:

- a lightweight meeting title header
- the full transcript body as continuous text

The transcript should be presented with comfortable padding and readable line spacing so it feels like a document. The first version should not introduce additional transcript chrome such as timestamps, chips, collapsible segments, or speaker markers.

### No Transcript Present

When no transcript exists, the center content area should show a simple empty state instead of blank space or metadata.

The empty state should include:

- the message `Not transcribed yet`
- a short supporting explanation that the meeting audio can be transcribed
- a prominent `Transcribe` button

This empty-state action should trigger the same transcription behavior as the sidebar action and follow the same enabled and disabled rules.

### Transcript Read Behavior

If the meeting points to a transcript file and the file can be read successfully, the view should display its contents in the main content area.

If the meeting points to a transcript path but the file is missing or unreadable, the center area should fall back to a friendly unavailable state rather than exposing raw file-system errors. The UI should stay simple and user-facing.

## Right Sidebar

The right sidebar should be fixed-width and always visible. It should be organized into the following sections in this order:

- `Details`
- `Actions`
- `Files`

### Details

The `Details` section should contain the meeting metadata currently shown in the main body:

- status
- started time
- ended time, when present
- duration, when available

This keeps meeting context visible without competing with the transcript.

### Actions

The `Actions` section should contain:

- `Transcribe`
- `Delete Meeting`

`Transcribe` remains visible here even when the main content also shows the empty-state transcribe button. Its enabled and disabled behavior should continue to follow the existing transcription eligibility rules.

`Delete Meeting` remains destructive and should preserve the current confirmation flow.

### Files

The `Files` section should contain technical artifact paths that are useful for debugging or advanced workflows:

- audio file path
- transcript file path, when present

These values should remain selectable text and visually secondary to the rest of the sidebar content.

## Bottom Playback Bar

Audio playback should move into a persistent docked bar at the bottom of the meeting detail view.

The bar layout should be:

- left: play or pause button
- center: playback progress slider
- right: combined elapsed and total time display

The simplest time treatment is a single right-aligned label such as `1:24 / 12:03`.

Playback should remain available whether the meeting has a transcript or not. If audio playback cannot load, the bottom bar should remain visible but disabled, with subtle status messaging still available so the user is not left with an unexplained broken control.

## Component Design

### MeetingDetailView

`MeetingDetailView` remains the screen entry point for a selected meeting, but its responsibility shifts from rendering a stacked detail form to composing the new three-region layout.

Responsibilities:

- load and display transcript content when available
- show the empty state when no transcript exists
- render the fixed right sidebar
- render the docked playback bar
- keep delete confirmation behavior
- keep existing playback loading behavior tied to meeting selection

### Transcript Content Helper

Introduce a small helper or view-local state path for resolving transcript display content from `meeting.transcriptFilePath`.

Responsibilities:

- determine whether a transcript exists
- read transcript text when available
- surface a simple UI state for present, absent, or unavailable transcript content

This logic should stay focused and testable rather than being buried inline across multiple view branches.

### MeetingAudioPlayback

The existing playback controller should continue to own playback state, file loading, seeking, and play or pause behavior.

This redesign should reuse that controller and adapt the view presentation around it instead of changing playback architecture.

## State Handling

- The screen continues to derive from the selected `Meeting`
- Playback reloads from the selected meeting audio file when selection changes
- The empty-state `Transcribe` button and the sidebar `Transcribe` button trigger the same action
- If transcript content exists, it becomes the primary content
- If transcript content does not exist, the empty state becomes the primary content
- Playback remains independent from transcript availability

This keeps the redesign focused on layout and presentation, not on new business logic.

## Error Handling

The redesign should preserve existing app behavior for operational errors:

- deletion keeps the existing confirmation dialog
- transcription errors continue to flow through the existing app-level alert handling

For transcript display:

- missing or unreadable transcript artifacts should produce a friendly unavailable state
- raw file-system or decoding errors should not be shown directly in the main content area

For playback display:

- if audio cannot be loaded, the bottom playback bar remains present
- controls are disabled when playback is unavailable
- existing playback status messaging remains available in a subtle supporting role

## Testing Strategy

Existing playback and view-model tests should remain the main safety net for transcription and playback behaviors that are not changing.

Add focused coverage for new transcript-display logic:

- transcript file path present and readable shows transcript content
- transcript file path absent shows the empty state
- transcript file path present but missing or unreadable shows the unavailable fallback state

Manual verification should cover:

- a transcribed meeting shows transcript text as the main content
- an untranscribed meeting shows `Not transcribed yet` with a `Transcribe` button
- the sidebar section order is `Details`, `Actions`, `Files`
- the bottom player stays docked with play or pause, progress, and time layout
- transcription still works from both entry points
- deletion still works with confirmation
- switching meetings refreshes transcript and playback state correctly

## Implementation Notes

- Follow existing SwiftUI structure and keep the change localized to the meeting detail experience
- Prefer small view extractions only where they improve readability of the new layout
- Avoid changing transcription service or playback internals unless a small interface adjustment is required by the layout
- Keep the first version visually simple and transcript-first
