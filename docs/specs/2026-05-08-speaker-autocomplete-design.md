## Speaker Autocomplete Design

### Goal
Use meeting attendee names as autocomplete suggestions in the speaker rename input. When attendee hints are available on a `Meeting`, the speaker input should show case-insensitive substring matches while typing and apply a clicked suggestion immediately.

### Scope
- Add autocomplete suggestions to the speaker rename input in the meeting detail sidebar.
- Source suggestions only from `meeting.attendeeNames`.
- Match suggestions using case-insensitive substring filtering.
- Apply a clicked suggestion immediately through the existing speaker rename flow.
- Preserve freeform speaker renaming when no attendee hints exist or no suggestions match.

### Non-Goals
- No new attendee sourcing logic beyond the existing `Meeting.attendeeNames` snapshot.
- No later calendar syncing or suggestion refresh behavior.
- No changes to transcript persistence or diarization logic.
- No requirement for keyboard navigation beyond what SwiftUI controls provide naturally.
- No new global autocomplete system for other inputs.

### Architecture
- Introduce a small `SpeakerNameInput` SwiftUI component dedicated to the speaker rename field.
- Keep `SpeakerNameInput` responsible for local draft text, suggestion filtering, and suggestion-list visibility.
- Keep `MeetingDetailView` responsible for supplying the current speaker name, the meeting attendee hints, and the existing rename callback.
- Preserve the existing `onRenameSpeaker(speakerID, displayName)` contract so the rest of the app does not need to understand autocomplete UI state.

### UI Behavior
- Each speaker row in the sidebar continues to render an inline text input.
- When `meeting.attendeeNames` contains values, typing into the field shows matching suggestions below the input.
- Suggestions are filtered by case-insensitive substring match against the current draft.
- Suggestions that are exact matches for the current draft should be omitted to avoid redundant options.
- If there are no attendee hints or no matches, no suggestion list is shown.
- Clicking a suggestion immediately updates the input draft, closes the suggestion list, and triggers the existing rename callback with the selected value.

### Data Flow
1. `MeetingDetailView` loads transcript speakers as it does today.
2. Each speaker row renders `SpeakerNameInput` with the current display name and `meeting.attendeeNames`.
3. `SpeakerNameInput` keeps a local draft string for the row being edited.
4. As the draft changes, the component computes filtered suggestions using case-insensitive substring matching.
5. Freeform typing continues to call back through the existing speaker rename path.
6. Clicking a suggestion sets the draft to the selected attendee name and immediately calls the same rename callback.
7. `ContentView` and `AppViewModel` continue to handle the rename exactly as they do today.

### Matching Rules
- Matching is case-insensitive.
- Matching is based on substring containment, not just prefix matching.
- Suggestion order should preserve the original order from `meeting.attendeeNames`.
- Duplicate attendee names may remain duplicated if they exist in `Meeting`, because this feature should not silently normalize the stored snapshot.
- Empty drafts should keep the suggestion list hidden until the user types at least one character.

### Failure Handling
- Missing attendee names is a normal state and should degrade to a plain speaker text field with no suggestion UI.
- Suggestion UI should not block manual entry if rename persistence fails; existing rename error handling remains the source of truth.
- If a clicked suggestion triggers a rename failure, the existing alert path should continue to surface that failure.

### Testing
- Add focused tests for case-insensitive substring filtering.
- Add focused tests for omitting exact-match suggestions.
- Add focused tests for immediate application when a suggestion is selected.
- Add focused tests proving no suggestions are shown when attendee hints are empty or when there are no matches.
- If a helper type is introduced for filtering and selection state, prefer testing that helper directly instead of trying to exhaustively UI-test SwiftUI rendering.

### Implementation Notes
- Keep the new component small and local to the meeting-detail feature unless a broader reuse case appears during implementation.
- Prefer extracting pure helper logic or a tiny row-scoped view model if that makes the filtering behavior easy to test.
- Reuse the current rename callback path rather than introducing a second persistence or commit mechanism for suggestion selection.
