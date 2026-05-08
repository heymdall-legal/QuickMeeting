## macOS Calendar Integration Design

### Goal
Add a first calendar integration for macOS that lets the user choose which calendars QuickMeeting should use and shows the next upcoming timed event for today on the Home screen. If calendar access is not granted, no calendars are selected, or no qualifying event exists for today, the Home screen should show nothing.

### Scope
- Add a new `Calendar` pane in Settings.
- Let the user explicitly request Calendar access from that pane.
- Load available calendars after access is granted.
- Persist the user's selected calendar identifiers in app settings.
- Select all available calendars by default on the first successful load when no prior selection exists.
- Show the next qualifying event for today on the Home screen.
- Exclude all-day events from the query.

### Non-Goals
- No auto-start recording from calendar events.
- No meeting title suggestion from calendar data yet.
- No attendee UI yet, even though attendee data should be available in the app-facing event model for later use.
- No error banners or alerts on the Home screen for calendar failures in this version.

### Architecture
- Add a dedicated calendar integration slice rather than calling EventKit directly from existing UI code.
- `CalendarAccessService` owns permission checks and the explicit access request flow.
- `CalendarIntegrationService` owns loading calendars and querying the next qualifying event for today.
- `CalendarSettingsStore` owns persistence of selected calendar identifiers using lightweight app settings storage such as `UserDefaults`.
- `CalendarSettingsViewModel` owns the Settings pane state, including permission status, available calendars, selected calendars, and the action to request access.
- `QuickMeetingApp` wires these dependencies once and passes them into the app layer.
- `AppViewModel` depends only on an app-facing calendar protocol and never on EventKit types directly.

### Settings UX
- Settings gains a new `Calendar` pane alongside the existing `Models` pane.
- If calendar access has not been granted, the pane shows a short explanation plus a `Grant Calendar Access` button.
- Pressing that button triggers the explicit permission request.
- When access is granted, the pane loads the user's available calendars and displays them in a multi-select list.
- On first successful load, if no saved calendar selection exists, the app selects all available calendars by default and persists that selection immediately.
- On later visits, the saved calendar identifiers remain the source of truth and the user can adjust them freely.

### Home Screen UX
- The Home screen stays quiet by default.
- If access is denied or not yet granted, show no calendar section.
- If no calendars are selected, show no calendar section.
- If there is no qualifying event for today, show no calendar section.
- If there is a qualifying event, show one compact section containing the event title and time range.
- The Home screen should not show calendar-specific error messaging in this first version.

### Event Selection Rules
- Query only events that occur today in the user's local calendar context.
- Exclude all-day events before ranking candidates.
- Exclude events whose `endDate` is less than or equal to `now`.
- Among the remaining events across all selected calendars, choose the event with the earliest start time.
- This allows an in-progress event to win over later upcoming events as long as it has not ended.

### Data Flow
1. `HomeView` appears.
2. `AppViewModel` requests the next qualifying event for today from the calendar integration service.
3. The service checks permission state.
4. The service loads the saved selected calendar identifiers.
5. The service resolves those identifiers to currently available EventKit calendars.
6. The service queries today's events for the resolved calendars.
7. The service filters out all-day events and already-ended events.
8. The service returns the earliest remaining event, or `nil` if no valid event exists.
9. `HomeView` renders a compact event section only when the result is non-`nil`.

### App-Facing Models
- Add a lightweight app-owned `UpcomingCalendarEvent` model instead of exposing EventKit objects through the app.
- `UpcomingCalendarEvent` should include `title`, `startDate`, `endDate`, and `attendees`.
- Add a lightweight attendee model for future use, such as display name plus optional email address, so later attendee features can build on app-owned data rather than raw EventKit types.
- Calendar name is not required for this first version.

### Failure Handling
- If saved calendar identifiers no longer resolve to live calendars, ignore the missing calendars.
- If all saved identifiers are stale, treat the query as having no usable selected calendars and return `nil`.
- If permission is revoked after setup, the integration should return `nil` for Home queries and Settings should fall back to the access-request state.
- Query or mapping failures should fail silently for the Home screen in this version and return `nil`.

### Testing
- Add settings-view-model tests for first-grant default selection to all available calendars.
- Add settings-view-model tests for toggling persisted calendar selections.
- Add calendar query tests proving only today's events are considered.
- Add calendar query tests proving all-day events are excluded.
- Add calendar query tests proving already-ended events are excluded.
- Add calendar query tests proving an in-progress event is preferred over a later upcoming event when its start time is earlier.
- Add calendar query tests proving `nil` is returned when access is denied, no calendars are selected, or no valid events exist.
- Add a lightweight `AppViewModel` or Home-screen-facing test proving `nil` results in no calendar section being shown.

### Future Extensions
- Reuse the same integration service to support calendar-based meeting title suggestions later.
- Extend the app-facing event and attendee models for richer meeting context without leaking EventKit types into the rest of the app.
- Use the same selected-calendar settings as the basis for future calendar-triggered recording or reminders if those features are added.
