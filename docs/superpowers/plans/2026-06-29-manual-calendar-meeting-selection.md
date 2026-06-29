# Manual Calendar Meeting Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a manual calendar meeting picker that updates a recording's title, attendee names, and stored calendar event ID.

**Architecture:** Extend the calendar model with an optional event ID and a candidate-events query. Add a MeetingStore update method that persists selected calendar metadata. Wire the detail view through AppViewModel and ContentView with a compact SwiftUI popover.

**Tech Stack:** Swift, SwiftUI, SwiftData, EventKit, Swift Testing, Xcode test runner.

---

### Task 1: Calendar Candidate API

**Files:**
- Modify: `QuickMeeting/Models/UpcomingCalendarEvent.swift`
- Modify: `QuickMeeting/Services/Calendar/CalendarIntegration.swift`
- Modify: `QuickMeeting/Services/Calendar/NativeCalendarIntegration.swift`
- Test: `QuickMeetingTests/NativeCalendarIntegrationTests.swift`

- [ ] Add `id: String?` to `UpcomingCalendarEvent` and `CalendarEvent`.
- [ ] Add `calendarEventsForRecording(startedAt:endedAt:) -> [UpcomingCalendarEvent]` to `CalendarIntegration`.
- [ ] Write a failing test that candidates include overlapping and same-day selected-calendar events, skip all-day and blank-title events, and preserve event IDs.
- [ ] Implement the candidate query by fetching the recording day from selected calendars, excluding invalid events, ranking overlapping events first and then nearest same-day events, and mapping attendees through existing organizer merge logic.
- [ ] Run `xcodebuild test -scheme QuickMeeting-Test -destination 'platform=macOS' -derivedDataPath /tmp/QuickMeetingDerivedData -only-testing:QuickMeetingTests/NativeCalendarIntegrationTests -quiet` through the repository's output filter.

### Task 2: Persist Selected Calendar Metadata

**Files:**
- Modify: `QuickMeeting/Models/Meeting.swift`
- Modify: `QuickMeeting/Services/MeetingStore.swift`
- Test: `QuickMeetingTests/MeetingStoreTests.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] Add a Meeting mutator for calendar metadata: title, attendee names, and calendar event ID.
- [ ] Extend `MeetingStore.createMeeting` to accept `calendarEventID`.
- [ ] Add `MeetingStore.updateCalendarEvent(meetingID:eventTitle:attendeeNames:calendarEventID:updatedAt:)`.
- [ ] Write failing tests for create-time event ID persistence and manual update persistence.
- [ ] Add an AppViewModel method that calls the store update and exposes calendar candidates for a meeting.
- [ ] Run focused MeetingStore and AppViewModel tests.

### Task 3: Detail Picker UI

**Files:**
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeeting/ContentView.swift`

- [ ] Add `calendarEvents`, `onReloadCalendarEvents`, and `onSelectCalendarEvent` inputs to `MeetingDetailView`.
- [ ] Add a calendar icon header action that opens a popover.
- [ ] Render candidate rows with title, time range, and attendee count.
- [ ] On selection, call `onSelectCalendarEvent`, dismiss the popover, and show a toast.
- [ ] Keep the picker available across non-active detail modes and avoid changing active-recording controls.

### Task 4: Verification

**Files:**
- Verify all files modified by Tasks 1-3.

- [ ] Run the focused calendar, store, and view-model tests.
- [ ] Run a targeted build or broader test slice if compilation errors point outside the focused suites.
- [ ] Inspect `git diff --stat` and `git diff --check`.
- [ ] Confirm unrelated existing changes in `.gitignore` and `QuickMeeting.xcodeproj/project.pbxproj` remain untouched by this feature.
