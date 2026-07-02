# Manual Calendar Meeting Selection Design

## Goal

Allow a user to manually replace the calendar meeting associated with a recording when automatic calendar matching picks the wrong overlapping or adjacent event.

## Behavior

- The meeting detail header exposes a calendar action for completed, recorded, transcribing, and loading recordings.
- Activating the action opens a compact popover with candidate calendar events near the recording time.
- Selecting an event updates the stored meeting title, attendee names, and calendar event identifier.
- Existing transcript audio, transcript text, speaker names, summary, and recording status are left untouched.
- Speaker rename suggestions immediately use the newly selected attendee names.
- If calendar access is missing or no nearby events are available, the popover shows an empty state instead of failing silently.

## Calendar Candidates

Candidate events come from the selected calendars already configured in settings. All-day events and blank-title events are excluded. Events are ranked by relevance for the recording: overlapping events first, then same-day events closest to the recording start.

The current automatic match can continue to choose one event at recording start, but manual selection gives the user an explicit correction path when multiple events overlap, a meeting started before recording, or two events share part of the same slot.

## Persistence

`Meeting.calendarEventID` already exists and is optional. This feature will start saving it when EventKit provides an event identifier. Older meetings remain valid with `nil`.

Manual selection stores a snapshot of the event title and attendee names. The ID is metadata for future features and is not used as the current source of truth for title or participants.

## UI Shape

The detail header keeps the current editable title. A small calendar icon button sits with the existing header actions. The popover shows event title, time range, and attendee count. Choosing a row dismisses the popover and shows a brief toast.

## Testing

- Calendar integration returns candidate events with IDs, excluding all-day and blank-title events.
- Automatic recording creation saves the matched event ID when present.
- Manual selection persists title, attendees, and event ID without changing transcript data.
- Detail header action availability can be covered through focused view-helper tests where possible.
