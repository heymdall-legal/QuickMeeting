# Screen Speaker Suggestions Design

## Goal

During a meeting recording, QuickMeeting should capture local screen evidence that can later suggest which calendar attendee corresponds to each diarized transcript speaker. Suggestions must stay suggestions only: the app never renames a speaker without an explicit user action. The user should be able to inspect the screenshot behind a suggestion in a small preview window before accepting it.

## Product Behavior

- While recording, the app periodically captures screen snapshots for the active meeting context.
- Snapshots are analyzed locally with macOS frameworks only. No screenshot or image data is sent to an external API.
- The analysis looks for calendar attendee names and visible active-speaker cues in meeting UI tiles.
- After transcription, each transcript speaker may show a proposed attendee match.
- A suggestion appears in the existing speaker rename popover as a compact card with:
  - proposed attendee name
  - short reason, such as "Seen in active tile"
  - confidence label
  - screenshot thumbnail
  - accept and dismiss actions
- Accepting a suggestion uses the existing speaker rename flow.
- Dismissing a suggestion hides that suggestion for the meeting.
- Clicking the thumbnail opens a small screenshot preview window so the user can verify the evidence.
- If the calendar event changes for a meeting, existing suggestions are invalidated and recomputed from the stored screen observations using the new attendee list.

## Scope

- Add a recording-time screen snapshot collector.
- Store reduced-size screenshots or cropped evidence images in the meeting folder.
- Add local OCR and tile-highlight analysis.
- Add a suggestion service that maps screen observations to transcript speakers and calendar attendees.
- Add UI for suggestion review, accept, dismiss, and screenshot preview.
- Add a Kontur Talk-focused analysis adapter as the first product-specific heuristic.
- Keep a generic meeting-grid fallback for other apps where active speaker tiles are visually highlighted.

## Non-Goals

- No automatic speaker renaming.
- No external vision or LLM APIs.
- No face recognition.
- No attempt to identify a person who is not in the selected calendar attendee list.
- No live UI interruption during recording.
- No guarantee that every speaker receives a suggestion.
- No browser extension or browser automation for reading `https://kontur.ru/talk` internals.

## Existing Context

The app already has the core pieces this feature should reuse:

- `Meeting.attendeeNames` stores the calendar attendee snapshot.
- `AppViewModel.selectCalendarEvent(...)` updates the meeting title, attendees, and calendar event ID.
- `MeetingDetailView` already has a speaker rename popover and calendar attendee suggestions.
- `AppViewModel.renameSpeaker(...)` persists a user-confirmed speaker rename and best-effort speaker enrollment.
- Recording permission flow already includes screen capture permission because audio capture uses ScreenCaptureKit.
- Meeting artifacts already live in a per-meeting folder managed by `MeetingFileStore`.

This feature should add a narrow visual-observation layer without making recording, transcription, or calendar integration depend on one another.

## Architecture

### Screen Observation Capture

Introduce a `MeetingScreenObservationCapturing` service that starts and stops alongside recording. It receives the meeting ID and meeting folder URL.

Responsibilities:

- Capture a snapshot every configured interval, such as every 8 to 15 seconds.
- Prefer the visible meeting window when it can be identified; otherwise capture the main display snapshot.
- Downscale and optionally crop images before storage.
- Save evidence images under the meeting folder, for example:
  - `screen-observations/0001.jpg`
  - `screen-observations/0001-thumb.jpg`
- Emit lightweight metadata:
  - observation ID
  - capture timestamp
  - image path
  - source window title and app bundle ID when available
  - OCR text boxes
  - candidate active-speaker tile boxes

The collector must be best-effort. If screen capture fails or permissions change, recording continues.

### Local Image Analysis

Introduce `ScreenObservationAnalyzer` behind a protocol so tests can provide deterministic observations.

The first implementation uses local macOS APIs:

- Vision text recognition for OCR.
- CoreGraphics image inspection for color, borders, and rectangular tile cues.
- Simple geometry grouping to associate OCR name boxes with participant tiles.

The output should be app-owned structured data rather than raw Vision objects:

- recognized text snippets with bounding boxes
- participant tile candidates
- active tile candidates
- attendee-name matches
- source image references

### Kontur Talk Adapter

Kontur Talk should get the first product-specific adapter because the user expects higher accuracy there.

The adapter is selected when evidence suggests the meeting UI is Kontur Talk. Since QuickMeeting cannot reliably read a browser URL without a browser extension, detection should use local signals:

- window title or owner app/title contains Kontur/Talk-related text when available
- OCR sees Kontur Talk UI words or attendee tiles
- the visible grid structure matches the expected Talk layout

The adapter should focus on:

- finding participant tile rectangles
- detecting the visually highlighted active-speaker tile
- reading the name label inside or near that tile
- giving higher confidence when an attendee name is OCR-matched inside the highlighted tile

Tuning should use a small local fixture set of Kontur Talk screenshots captured by the developer or tester. Fixtures should be sanitized or kept out of source control if they contain real meeting content.

The generic fallback should use the same observation model but lower confidence thresholds. This keeps other apps useful while making Kontur Talk the place where we tune precision first.

### Active Speaker Highlight Detection

Most meeting apps highlight the current speaker by changing a tile border, background, shadow, or outline. The analysis should treat this as evidence, not truth.

Recommended local heuristic:

1. Detect rectangular video/avatar tiles.
2. Find high-contrast or brand-colored border/outline regions around tiles.
3. Associate nearby OCR name labels with each tile.
4. Mark a tile as active when its border or visual emphasis is materially stronger than nearby tiles.
5. Store a cropped screenshot around the active tile as evidence.

Confidence should increase when:

- a calendar attendee name is recognized inside the active tile
- the same attendee is active across multiple observations near speech from one diarized speaker
- the observation timestamp overlaps audio segments for that speaker

Confidence should decrease when:

- OCR only sees a partial name
- multiple attendees match the same text
- multiple tiles are highlighted
- no segment timing overlap is available

### Suggestion Generation

Introduce `SpeakerIdentitySuggestionService`.

Inputs:

- meeting ID
- current `meeting.attendeeNames`
- stored transcript speakers and segments
- screen observations and their timestamps
- dismissed suggestion state

Output:

- suggestion ID
- transcript speaker ID
- proposed attendee name
- confidence bucket: low, medium, high
- reason text
- evidence screenshot path
- capture timestamp
- status: pending, accepted, dismissed, superseded

The service should compute suggestions after transcription completes and whenever calendar attendees change. It can also be callable from the meeting detail screen when suggestions are missing.

The first MVP can use a conservative rule:

- only suggest names from the current meeting attendee list
- require at least one active-tile OCR match
- map a match to the transcript speaker whose segment overlaps the observation timestamp
- if no overlap exists, keep the observation available but do not suggest automatically

Later refinements can aggregate across multiple screenshots and use stronger scoring.

### Calendar Change Recompute

When `AppViewModel.selectCalendarEvent(...)` succeeds:

1. The meeting title, attendee names, and calendar event ID are updated as today.
2. Pending speaker suggestions for that meeting are marked superseded or removed.
3. The suggestion service reruns analysis against the stored observations using the new attendee list.
4. Accepted speaker names are not automatically reverted.
5. Dismissed suggestions for the old attendee list do not block newly computed suggestions for different attendees.

This keeps screenshots as durable evidence while making attendee matching reflect the selected calendar event.

## Persistence

### Files

Screen images should live in the meeting artifact folder. Store downscaled JPEGs and small thumbnails rather than full-resolution display screenshots by default.

### SwiftData

Add persisted models for indexed suggestion state and observation metadata:

- `PersistedScreenObservation`
- `PersistedScreenTextObservation`
- `PersistedSpeakerIdentitySuggestion`

Do not store large image data in SwiftData. Store relative file paths into the meeting folder.

### Privacy

- Screen captures stay on-device.
- Store reduced evidence images by default.
- The user should be able to delete a meeting and remove all screenshots with the existing artifact-folder deletion path.
- Future settings may add a toggle for screen-evidence capture, but the MVP can keep this feature behind the same recording flow if the product direction is to always support suggestions.

## UI Design

### Speaker Popover

Extend the existing speaker rename popover in `MeetingDetailView`.

When a pending suggestion exists for that speaker, show a compact evidence card above regular calendar suggestions:

- "Suggested: Masha"
- "Seen in active tile"
- confidence label
- thumbnail
- checkmark button to accept
- xmark button to dismiss

Accepting calls the existing speaker rename path and marks the suggestion accepted. Dismissing marks it dismissed without changing transcript data.

### Screenshot Preview

Add a small auxiliary preview window or popover for the evidence image.

Behavior:

- opens from the suggestion thumbnail
- shows the evidence crop or full downscaled screenshot
- highlights the matched tile if coordinates are available
- includes the capture time
- does not require leaving the transcript screen

## Error Handling

- Failure to capture screenshots must not block recording.
- Failure to analyze a screenshot must not block recording or transcription.
- Missing screen recording permission should surface as "no screen evidence available" rather than a recording failure if audio capture can proceed.
- Missing attendees means no identity suggestions, but screenshots can still be collected.
- Missing transcript timing means observations are retained but speaker matching is skipped.
- Stale suggestions after calendar changes are hidden until recompute finishes.

## Testing

Add focused tests around pure logic first.

- Matching only proposes names from the current attendee list.
- Active-tile OCR evidence creates a high-confidence suggestion when it overlaps a speaker segment.
- Non-overlapping evidence does not assign a suggestion to a speaker.
- Calendar attendee changes invalidate old pending suggestions and recompute from existing observations.
- Accepted suggestions are not reverted by calendar recompute.
- Dismissed suggestions are not shown again for the same speaker and attendee.
- Kontur Talk adapter prefers highlighted tile evidence over plain OCR elsewhere on screen.

UI tests can be limited to view-model or helper tests that prove the popover chooses the suggestion card state, with manual visual QA for the preview window.

## Rollout

Implement in thin vertical slices:

1. Data models and pure suggestion scoring tests.
2. Screenshot file storage and recording lifecycle hook.
3. Local OCR observation analysis.
4. Kontur Talk active-tile heuristic.
5. Suggestion recompute after transcription and calendar change.
6. Speaker popover suggestion card and screenshot preview.

The first shipped version should prefer false negatives over false positives. A quiet missing suggestion is better than a confident wrong name.
