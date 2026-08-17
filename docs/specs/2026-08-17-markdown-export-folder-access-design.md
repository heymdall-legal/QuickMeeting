# Markdown export folder access recovery

## Goal

Keep automatic Markdown exports usable when macOS no longer grants access to a
previously selected export directory.

## Behaviour

- Every configured Markdown export resolves the saved security-scoped bookmark
  and opens its scoped access for the whole filesystem operation.
- A bookmark that cannot provide access is treated as an unavailable export
  destination. The export is not attempted without access.
- When the user selects a folder and the initial backfill cannot access it, the
  selected directory setting is cleared. Settings show an actionable error that
  asks the user to choose the folder again.
- Selecting a replacement folder persists a fresh bookmark and immediately
  backfills existing transcripts and summaries.

## Implementation boundaries

- `MeetingMarkdownExportSettingsStore` remains responsible for bookmark
  persistence and resolution.
- `ConfiguredMeetingMarkdownExporter` owns the scoped-access lifetime and
  reports a dedicated unavailable-directory error when access cannot start.
- `MarkdownExportSettingsViewModel` clears a failed new selection and exposes
  the recovery message to the existing Settings alert.

## Testing

- Add a regression test that makes scoped access unavailable and asserts that
  no export write is attempted.
- Preserve the existing successful-selection/backfill coverage.

## Scope

This changes only automatic Markdown export folder access. It does not alter
file naming, export contents, or any other filesystem permissions.
