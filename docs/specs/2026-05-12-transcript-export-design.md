# Transcript Export Design

## Goal

Add an export action for a transcribed meeting that copies a Markdown representation of the meeting transcript to the user's clipboard.

## User Experience

- The meeting detail view shows an `Export Transcript` button when transcript content is available.
- Clicking the button copies Markdown to the macOS clipboard.
- After a successful copy, the UI shows brief inline feedback near the button with the text `Copied`.
- The feedback clears automatically after a short delay so the action area returns to its normal state.

## Export Format

The exported Markdown must use this shape:

```md
# {meeting title}

Date: **YYYY-MM-DD HH:mm**

Duration: **HH:mm**

## {speaker name 1}
...
```

Formatting rules:

- The title uses the meeting title. If the title is empty, export `Untitled Meeting`.
- The date uses the meeting start timestamp formatted as `YYYY-MM-DD HH:mm`.
- The duration uses the meeting duration formatted as `HH:mm`.
- Consecutive segments from the same speaker are grouped under one `## Speaker Name` heading.
- Within a speaker section, consecutive transcript segments are separated by a blank line.
- Empty transcript segments are ignored after trimming whitespace.
- If a segment has no matching speaker, export it under `## Speaker`.

## Architecture

Add a small formatter dedicated to export Markdown generation rather than reusing the artifact writer directly.

Responsibilities:

- Formatter:
  - Accepts `Meeting` and `StoredTranscript`
  - Produces the clipboard Markdown string
  - Owns header formatting and speaker grouping
- Meeting detail view:
  - Determines whether export is available
  - Invokes the formatter
  - Writes the string to the clipboard
  - Shows temporary `Copied` feedback

This keeps AppKit clipboard behavior in the UI layer and keeps formatting logic isolated and easy to test.

## UI Changes

Update the meeting detail action area to include the export action alongside the existing transcription controls.

Behavior:

- The export button is enabled only when a meeting has a transcript with at least one non-empty segment.
- Copy feedback is shown inline in the same action row, not as an alert.
- Failed transcript loading continues to hide or disable export rather than attempting a partial export.

## Error Handling

- If no transcript content is available, the export action is unavailable.
- Clipboard writes are treated as best-effort UI work; no separate error alert is added for this iteration.
- Missing duration exports as `00:00` so the file header stays structurally consistent.

## Testing

Add tests for:

- Full Markdown rendering including title, date, duration, and grouped speaker sections
- Fallback values for untitled meetings, unknown speakers, and missing duration
- Export availability based on transcript content

No new persistence or database behavior is required.
