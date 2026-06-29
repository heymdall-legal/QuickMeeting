# Obsidian Markdown Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a configurable Obsidian Markdown export folder for transcript and summary files, including backfill for existing meetings.

**Architecture:** Keep SwiftData as the source of truth and add a small Markdown export service that mirrors meeting data to `.md` files when enabled. Store the selected folder path in `UserDefaults`, expose it in Settings, and trigger best-effort exports from existing meeting mutation points.

**Tech Stack:** Swift, SwiftData, SwiftUI `fileImporter`, UserDefaults, Swift Testing.

---

### Task 1: Markdown Export Service

**Files:**
- Create: `QuickMeeting/Services/MarkdownExport/MeetingMarkdownExportSettingsStore.swift`
- Create: `QuickMeeting/Services/MarkdownExport/MeetingMarkdownExporter.swift`
- Test: `QuickMeetingTests/MeetingMarkdownExporterTests.swift`

- [ ] Write failing tests for settings persistence, transcript rendering, summary rendering, and stale UUID-matching file replacement.
- [ ] Implement settings storage with an optional directory path.
- [ ] Implement an exporter that writes `.transcript.md` and `.summary.md` files with YAML frontmatter and Obsidian-friendly Markdown bodies.
- [ ] Run targeted exporter tests.

### Task 2: Store Integration And Backfill

**Files:**
- Modify: `QuickMeeting/Services/MeetingStore.swift`
- Test: `QuickMeetingTests/MeetingStoreTests.swift`

- [ ] Write failing tests proving `completeTranscription`, `saveSummary`, `renameSpeaker`, and `renameMeeting` trigger Markdown export when an exporter is configured.
- [ ] Add optional exporter dependency to `MeetingStore`.
- [ ] Add `fetchMeetings()` and `exportMarkdownForExistingMeetings()` for migration/backfill.
- [ ] Call exporter best-effort after relevant store mutations.
- [ ] Run targeted `MeetingStoreTests`.

### Task 3: Settings UI

**Files:**
- Create: `QuickMeeting/ViewModels/MarkdownExportSettingsViewModel.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeeting/ContentView.swift`
- Modify: `QuickMeeting/Views/Settings/QMSettingsSheet.swift`

- [ ] Add a view model that exposes the selected folder path and triggers backfill after selection.
- [ ] Wire the shared settings store/exporter into app construction.
- [ ] Add a Settings row with folder picker, selected path text, and clear action.
- [ ] Run a targeted build/test command for the app target and touched tests.

### Task 4: Verification

- [ ] Run focused Swift tests for Markdown exporter, settings view model, and store integration.
- [ ] Run a build or narrow test command that compiles the app target.
- [ ] Inspect `git diff --stat` and relevant diffs before final response.
