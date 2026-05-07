# Transcript UI Rendering

## Summary

QuickMeeting will stop rendering meeting transcripts in the UI as markdown-like plain text and instead present structured transcript segments directly. The new transcript view will show bold speaker names, optional left-aligned segment start times, and cleaner spacing between segments while preserving markdown rendering for export and artifact generation.

This change is intentionally limited to transcript presentation inside the meeting detail screen. It does not change transcription generation, export formats, or transcript persistence.

## Goals

- Replace markdown-like transcript rendering in the app UI with structured transcript presentation
- Show speaker names in bold at the start of each segment
- Show a single visual break between transcript segments
- Support optional segment start times in the transcript view
- Make segment times visible but visually secondary
- Prevent segment times from being copied when users select transcript text
- Add a local display toggle in the right-hand metadata area for showing or hiding segment times

## Non-Goals

- Changing how transcript markdown is generated for export or stored artifacts
- Persisting transcript display preferences across launches or meetings
- Editing transcript text inline
- Changing diarization, speaker assignment, or transcript ordering logic
- Adding transcript search, filtering, or segment collapsing

## Product Decisions

- Transcript UI rendering should use structured `StoredTranscript` data rather than markdown text
- Markdown conversion remains available for export-oriented paths
- The segment time display toggle lives only in `MeetingDetailView`
- Segment times are hidden by default
- Segment times appear in a narrow left column when enabled
- Segment times are not selectable
- Transcript text remains selectable
- Speaker names appear inline at the beginning of each segment in bold styling

## UX Design

### Transcript Layout

When a transcript is available, the main content area will render one row per transcript segment.

Each row has two columns:

- an optional timestamp column on the left
- a text column on the right

The timestamp column should be narrow, visually stable, and aligned so repeated timestamps scan easily down the page. The text column should take the remaining width and remain the primary reading surface.

### Speaker and Text Styling

If a segment has a resolved speaker name, the UI should render that name in bold at the beginning of the segment text. The speaker name should read as part of the segment rather than as a separate block heading.

If a segment has no speaker identifier or no matching speaker, the transcript should still render the segment text without inserting placeholder labels.

Segment text should be trimmed for leading and trailing whitespace so the rendered transcript does not inherit awkward spacing from the transcription pipeline.

### Segment Spacing

The transcript should read like a clean conversation transcript rather than a markdown document. Each segment should have a single visual separation from the next segment, matching the desired `\n`-style flow rather than the current heading-plus-paragraph spacing.

### Timestamp Styling

When visible, segment start times should:

- appear to the left of the transcript text
- use a small font
- use a secondary gray style that remains readable
- stay visually aligned across rows
- remain non-selectable so copied transcript text does not include timestamps

If a segment has no start time, the row should still align correctly. The timestamp column should reserve its width and render no timestamp text for that row.

## Right Sidebar Toggle

Add a transcript display control in the right-hand sidebar as its own `Transcript Display` section so the control is easy to discover without crowding the meeting metadata.

The section contains:

- a `Show segment times` toggle

Behavior:

- the toggle defaults to `off`
- the toggle state is local view state only
- the toggle affects only the currently displayed meeting detail view
- reopening the meeting detail view resets the toggle to hidden

No persistence layer, settings store, or meeting model field should be introduced for this preference.

## Architecture

### Transcript Content Model

The UI transcript-loading path should stop flattening `StoredTranscript` into markdown text. Instead, the transcript display path should return structured data suitable for direct rendering.

This can be represented either as:

- a new `MeetingTranscriptContent` case that carries `StoredTranscript`
- or a small dedicated display model derived from `StoredTranscript`

The key requirement is that the view receives transcript segments and speaker metadata separately from markdown export logic.

### MeetingDetailView

`MeetingDetailView` remains the screen entry point and gains one local state property for timestamp visibility.

Responsibilities:

- load structured transcript display content
- hold local `showSegmentTimes` state, defaulting to `false`
- render the transcript view when transcript data exists
- pass the timestamp visibility flag into the transcript renderer
- show the new sidebar toggle alongside the existing metadata and actions

### Transcript Renderer

The transcript renderer should be responsible only for presentation of already-loaded transcript data.

Responsibilities:

- render rows in transcript order
- resolve speaker display names from the provided speaker list
- format timestamp text from segment start times
- keep timestamps visually separate from selectable transcript text
- apply readable spacing and typography

This renderer may replace the current `TranscriptTextView` or repurpose it behind a richer interface, but it should no longer accept a markdown-like transcript string as its primary input.

### Export Path

`TranscriptionArtifactWriter.renderMarkdown(from:)` remains unchanged and continues to own markdown generation for transcript artifacts and future export workflows.

This keeps export formatting decoupled from on-screen presentation.

## Data Flow

1. `MeetingDetailView` reads `meeting.storedTranscript`.
2. Transcript content helpers transform that transcript into structured display content.
3. `MeetingDetailView` stores the result in view state and passes it into the transcript renderer.
4. The sidebar toggle flips local `showSegmentTimes` state.
5. The transcript renderer updates layout to show or hide the timestamp column without changing transcript data.

No transcript persistence or conversion logic changes as part of this display toggle.

## Error Handling

- If no transcript exists, the existing empty transcript state remains unchanged.
- If transcript content is unavailable, the existing unavailable state remains unchanged.
- If a segment lacks a speaker or start time, the renderer should gracefully omit that decoration rather than fail the entire transcript view.

The transcript renderer should be tolerant of partial transcript metadata because display data may evolve over time.

## Testing Strategy

Update transcript-content tests so UI-facing helpers assert structured transcript loading rather than markdown string generation.

Add focused unit coverage for:

- loading structured transcript content from `StoredTranscript`
- preserving transcript segment ordering in display content
- resolving speaker names correctly
- omitting unresolved speaker labels
- formatting segment times for display
- leaving timestamp visibility as a view-only concern rather than a model concern

Manual verification should cover:

- a transcribed meeting shows each segment as a separate visual row
- speaker names render in bold
- transcript text remains selectable
- enabling `Show segment times` reveals a small gray timestamp column
- disabling `Show segment times` removes timestamps and expands transcript text
- copying transcript text does not include timestamps
- the toggle resets to hidden when the detail view is recreated

## Implementation Notes

- Keep the change localized to transcript presentation code and the meeting detail sidebar
- Reuse existing transcript ordering from `meeting.storedTranscript`
- Avoid introducing persistence for display-only state
- Keep markdown rendering code intact for export paths
