## Meeting Autonaming Design

### Goal
Add automatic meeting naming at recording start. When a recording begins, QuickMeeting should choose the title once and persist it with the meeting. If calendar access is already authorized and a matching calendar event is found, use that event title. Otherwise, use the fallback timestamp format `MM-dd HH:mm`.

### Scope
- Resolve the initial meeting title exactly once when recording starts.
- Use calendar data only when access has already been granted.
- Match a calendar event when its start time is within the inclusive window from 10 minutes before recording start through 5 minutes after recording start.
- Use the first matching event when multiple events match.
- Fall back to timestamp naming when calendar access is unavailable, no calendars are selected, no event matches, or the matched event title is empty.

### Non-Goals
- No permission prompt during recording start.
- No renaming after recording has already started.
- No changes to manual rename behavior.
- No new calendar UI beyond reusing the existing selected-calendar settings.

### Architecture
- Keep `AppViewModel.startRecording()` as the single place that determines the initial title for a new meeting.
- Introduce a small app-facing meeting title resolver that accepts the recording `startedAt` date and returns the chosen title.
- The resolver owns fallback formatting and delegates calendar matching to the calendar integration slice.
- Extend the calendar integration slice with a focused query for the first event matching a recording start date, instead of reusing the Home screen's upcoming-event query.
- `MeetingStore.createMeeting(...)` continues to receive a final title string and does not need to know whether that title came from the calendar or the fallback formatter.

### Matching Rules
- The fallback title format is `MM-dd HH:mm` in the user's current locale/time zone context for the recording start date.
- A calendar event qualifies only if its `startDate` falls within the inclusive range:
  - `startedAt - 10 minutes`
  - `startedAt + 5 minutes`
- Event end time does not affect matching once the start time is inside the window.
- All-day events should be excluded from matching.
- If multiple events qualify, sort by `startDate` ascending and then `endDate` ascending, and use the first result.
- If the chosen event title is empty or whitespace-only, treat it as unusable and fall back to the timestamp title.

### Data Flow
1. `AppViewModel.startRecording()` captures `startedAt`.
2. The meeting title resolver builds the fallback timestamp title from `startedAt`.
3. The resolver asks the calendar integration for the first matching event around `startedAt`.
4. The calendar integration checks authorization state.
5. If authorization is not `.authorized`, it returns no match.
6. If authorization is granted, it loads the user's selected calendar identifiers.
7. It resolves those identifiers to available calendars and queries events only in the bounded matching window.
8. It filters out all-day events and non-matching start times.
9. It sorts the remaining events and returns the first event with a non-empty title.
10. The resolver returns that event title, or the fallback timestamp title if no usable match exists.
11. `MeetingStore.createMeeting(...)` persists the selected title with the new meeting.

### Example Cases
- Event starts at `10:00`, recording starts at `09:54`: no match, use `MM-dd HH:mm`.
- Event starts at `10:00`, recording starts at `09:55`: match, use event title.
- Event starts at `10:00`, recording starts at `10:10`: match, use event title.
- Event starts at `10:00`, recording starts at `10:11`: no match, use `MM-dd HH:mm`.

### Failure Handling
- Denied or not-yet-determined calendar access is a normal fallback case and should not surface a recording error.
- If no calendars are selected, fall back silently.
- If saved calendar identifiers are stale, ignore the missing calendars and use any that still resolve.
- If no selected identifiers resolve to live calendars, fall back silently.
- If the calendar query fails for any reason, return no match and use the fallback timestamp title.

### Testing
- Add calendar integration tests for the boundary cases `09:54`, `09:55`, `10:10`, and `10:11` against a `10:00` event.
- Add tests proving unauthorized access and no selected calendars both produce no match.
- Add a test proving all-day events are excluded from autonaming matches.
- Add a test proving overlapping or otherwise multiple matches pick the first sorted event.
- Add a test proving an empty matched event title falls back to the timestamp title.
- Add an `AppViewModel` test proving a matched event title is persisted when recording starts.
- Add an `AppViewModel` test proving the fallback timestamp title is persisted when no usable match exists.

### Implementation Notes
- Prefer a dedicated date formatter dependency or helper for timestamp naming so the format is easy to test deterministically.
- Keep the title resolver side-effect free: it should not request permissions, save settings, or rename meetings after creation.
- Reuse the existing selected-calendar settings store rather than introducing separate autonaming calendar preferences.
