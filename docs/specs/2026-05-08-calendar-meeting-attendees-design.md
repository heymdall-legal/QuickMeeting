## Calendar Meeting Attendees Design

### Goal
Attach meeting attendee display names to `Meeting` when recording starts and a matching calendar event is found. This attendee snapshot will later be used as diarization-name hints. If no matching event exists, no calendars are selected, or calendar access is unavailable, persist an empty attendee list instead.

### Scope
- Add a plain `[String]` attendee-name snapshot to `Meeting`.
- Populate that snapshot exactly once when a meeting is created at recording start.
- Source attendee names from the same matched calendar event already used for automatic meeting naming.
- Persist attendee names exactly as returned from the matched event, without trimming, deduping, or filtering.
- Leave the stored attendee list empty when no matching calendar event is available.

### Non-Goals
- No later rematching of an existing recording to a calendar event.
- No attendee syncing after recording has started.
- No attendee UI in the meeting detail or Home screen.
- No permission prompt during recording start.
- No diarization changes yet beyond making the names available on `Meeting`.

### Architecture
- Keep `AppViewModel.startRecording()` as the single meeting-start boundary that resolves calendar-derived meeting metadata.
- Extend the meeting-start resolution step so it derives both the initial title and the attendee-name snapshot from the matched event.
- Keep `MeetingStore.createMeeting(...)` responsible for persisting the final meeting snapshot, including attendee names, but not for performing any calendar lookups itself.
- Reuse the existing calendar integration event-matching query and app-owned event model rather than introducing a second calendar lookup path.

### Recording-Start Flow
1. `AppViewModel.startRecording()` captures `startedAt`.
2. The view model asks the calendar integration for the event matching that recording start time.
3. If a matching event exists, the view model uses its title for meeting naming and `event.attendees.map(\.displayName)` for the attendee snapshot.
4. If no matching event exists, the view model uses the fallback timestamp title and an empty attendee list.
5. `MeetingStore.createMeeting(...)` persists the chosen title, the audio artifact metadata, and the attendee snapshot as part of the initial insert.
6. No later app flow updates `Meeting` attendees after creation.

### Data Model
- `Meeting` gains a stored attendee-name collection, represented as `[String]`.
- The attendee-name collection defaults to `[]` so meetings without calendar context remain valid.
- The stored values are a snapshot of the matched event at recording start, not a live view of calendar data.
- The existing app-facing calendar attendee model remains unchanged for this feature because meeting persistence only needs the display name strings.

### Failure Handling
- Denied or not-yet-determined calendar access is a normal fallback case and should not block recording start.
- No selected calendars is a normal fallback case and should not block recording start.
- No matching event is a normal fallback case and should not block recording start.
- A matched event with zero attendees should produce an empty attendee list and still allow the matched title to be used.
- Recording startup failures should keep the existing rollback behavior for the meeting row and artifacts directory.

### Testing
- Add an `AppViewModel` test proving a matched event title and attendee display names are both persisted when recording starts.
- Add an `AppViewModel` test proving the attendee list is empty when no matching event exists.
- Add a `MeetingStore` persistence test proving attendee names survive a fresh SwiftData context after `createMeeting(...)`.
- Optionally extend a calendar integration mapping test with non-empty attendees to guard against accidentally dropping attendee data while constructing `UpcomingCalendarEvent`.

### Implementation Notes
- Prefer resolving the matched event once during `startRecording()` and reusing it for both title and attendee extraction, rather than issuing separate calendar queries.
- Keep attendee persistence intentionally narrow: plain strings only, no email addresses, IDs, or separate persisted attendee model.
- Preserve the current quiet fallback behavior so calendar unavailability remains invisible during recording start.
