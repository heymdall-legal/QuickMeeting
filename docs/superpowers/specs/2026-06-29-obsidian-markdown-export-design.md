# Obsidian Markdown Export Design

## Goal

Allow users to choose a directory where QuickMeeting keeps Markdown copies of meeting transcripts and summaries for Obsidian.

## Design

SwiftData remains the source of truth for meetings, transcript structure, speakers, and summaries. A new Markdown export layer mirrors completed transcript and summary data into a user-selected folder. The selected folder path is stored in `UserDefaults`; when it is absent, export is disabled and the app behaves as it does today.

Each exported file uses a stable UUID-bearing filename:

- `yyyy-MM-dd sanitized-title <meeting-id>.transcript.md`
- `yyyy-MM-dd sanitized-title <meeting-id>.summary.md`

The UUID prevents collisions and lets re-exports replace the current file even after title changes. The files contain YAML frontmatter with meeting metadata useful in Obsidian: meeting ID, title, start/end timestamps, duration, status, attendees, source audio path, export type, and export timestamp. Transcript files then render speaker-grouped Markdown transcript content. Summary files render the stored summary text.

## Migration

When the user chooses a folder, QuickMeeting runs a backfill over existing meetings. Meetings with a stored transcript produce a transcript Markdown file; meetings with a stored summary produce a summary Markdown file. Existing export files for the same meeting and type are removed before writing the new file, so renames and date/title changes do not leave stale UUID-matching copies.

## Integration Points

`MeetingStore` triggers best-effort export after transcript completion, summary save, speaker rename, and meeting rename. Export failures should not block the primary app action. Settings exposes a folder picker and shows the selected path. A migration action runs automatically when the path is saved.

## Testing

Unit tests cover Markdown rendering, stable filenames, stale export replacement, settings persistence, and migration/backfill from existing SwiftData meetings.
