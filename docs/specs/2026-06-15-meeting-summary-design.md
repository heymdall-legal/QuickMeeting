# Meeting Summary Design

## Goal

Connect the existing meeting summary UI and summarization service so users can generate summaries from recorded transcripts, configure the LLM settings from the Settings sheet, and persist generated summaries on each meeting.

## Scope

In scope:

- Wire the existing summarization settings UI to persisted settings
- Validate that a meeting has transcript content before summarization starts
- Render a prompt template with `{text}` and `{date}` placeholders
- Call an OpenAI-compatible API with a configured base URL, auth token, and model name
- Persist generated summaries on meetings
- Show stored summaries in the meeting detail UI
- Require confirmation before replacing an existing stored summary
- Cover the behavior with targeted tests

Out of scope:

- Streaming responses
- Additional model parameters such as temperature, top-p, or max tokens

## User Settings

Use the existing `MeetingSummarySettingsStore` backed by `UserDefaults`.

Persisted values:

- `baseURL`
- `authToken`
- `modelName`
- `promptTemplate`

Behavior:

- Reads return the raw persisted strings for direct UI binding.
- The service uses a validated read path that trims whitespace and treats empty values as missing.
- Missing settings fail fast before any network request is built.

Add a focused `MeetingSummarySettingsViewModel` that:

- Loads current persisted values on initialization
- Exposes bindable fields for the settings sheet
- Saves edits back through `MeetingSummarySettingsStore`
- Supplies the default prompt template when the stored value is missing

`QMSettingsSheet` should stop using local `@State` for AI summarization settings and bind to the real view model instead.

## Prompt Rendering

The prompt template is a plain string with two supported placeholders:

- `{text}`: replaced with rendered transcript text
- `{date}`: replaced with the meeting recording date formatted as `YYYY-MM-DD`

All other text remains literal. There is no conditional logic, escaping syntax, or additional placeholder support in this iteration.

`{date}` uses `meeting.startedAt` with an `en_US_POSIX` formatter and `yyyy-MM-dd` format.

`{text}` reuses the existing transcript export formatting path, but in a body-only mode:

- No title header
- No date header
- No duration header
- Speaker sections remain grouped under `## Speaker Name`
- Consecutive lines from the same speaker remain grouped with blank lines between segments
- Empty transcript segments are ignored after trimming whitespace
- Unknown speakers continue to render as `Speaker`

To support this, extend `MeetingTranscriptExport` with a rendering mode or companion helper rather than duplicating transcript formatting inside the summary service.

## Service Architecture

Keep `MeetingSummaryService` as the summary generation boundary with the existing async entry point:

```swift
func summarize(meetingID: UUID) async throws -> String
```

Responsibilities:

- Load the meeting from `MeetingStore`
- Verify a transcript exists and contains usable content
- Load and validate summarization settings
- Render prompt template values
- Build and send the OpenAI-compatible request
- Parse the response and return summary text to the caller

Dependencies:

- `MeetingStore`
- `MeetingSummarySettingsStore`
- A small injectable HTTP transport seam for testing
- Date formatting and JSON encoding/decoding helpers kept private to the service module

This keeps meeting lookup, settings, transcript rendering, and network transport separated so `AppViewModel` can coordinate persistence and UI behavior without owning low-level request construction.

## Summary Persistence

Extend `Meeting` to store the generated summary text directly on the meeting record.

New persisted behavior:

- Meetings may have zero or one stored summary
- Saving a summary updates the meeting `updatedAt`
- Starting or completing transcription clears any previously stored summary because the transcript content has changed

Add `MeetingStore` APIs for:

- Reading the stored summary through the existing meeting fetch path
- Saving or replacing a summary for a meeting

Persisting on `Meeting` keeps summary data aligned with the transcript and available immediately when the user reopens the app.

## UI Wiring

`MeetingSummaryPane` remains a presentational view, but its state must now come from real meeting data and view-model actions.

Display rules:

- If a meeting has no stored summary and generation is idle, show the empty state and `Generate Summary`
- If generation is in flight, show the loading state
- If a stored summary exists, show the summary content from the meeting record
- If the latest generation attempt fails, show the error state with retry affordance

Interaction rules:

- Generate with no existing summary: start generation immediately
- Generate with an existing summary: ask for confirmation before replacement
- Confirm replacement: run summarization and overwrite the stored summary on success
- Cancel replacement: leave the existing summary unchanged and visible

The confirmation should be owned by the screen-level view model flow rather than by `MeetingSummaryPane`, so the pane stays reusable and stateless.

## View-Model Flow

`AppViewModel` should own summary generation, replacement confirmation, and surfaceable errors.

Add state for:

- The meeting currently being summarized, if any
- Summary generation errors
- A pending confirmation target when the user tries to regenerate a meeting that already has a stored summary

Flow:

1. User requests summary generation
2. `AppViewModel` checks whether the meeting already has a stored summary
3. If not, generation starts immediately
4. If yes, `AppViewModel` exposes a confirmation state
5. On confirmation, `AppViewModel` calls `MeetingSummaryService`
6. On success, `AppViewModel` persists the returned text through `MeetingStore`
7. On failure, `AppViewModel` leaves the old summary untouched and exposes the error

This ensures accidental clicks cannot destroy an existing summary and that persistence only changes on successful regeneration.

## Request Contract

The service will call an OpenAI-compatible chat completions endpoint using the user-provided base URL.

URL behavior:

- If the configured base URL already ends with `/chat/completions`, use it directly.
- Else if it ends with `/v1`, append `/chat/completions`.
- Else append `/v1/chat/completions`.

Request headers:

- `Authorization: Bearer <authToken>`
- `Content-Type: application/json`

Request body:

```json
{
  "model": "<modelName>",
  "messages": [
    {
      "role": "user",
      "content": "<rendered prompt>"
    }
  ]
}
```

No system message is added in this iteration. The full instruction set lives in the user-configured prompt template.

## Response Parsing

Parse the standard OpenAI-compatible response shape and extract the first available assistant message content from `choices[0].message.content`.

Success rules:

- Return the extracted content trimmed of surrounding whitespace.
- If the extracted content is empty after trimming, treat the response as invalid.

The service only needs text output in this iteration. It does not support tool calls, streamed chunks, or multipart content shapes unless they appear as a simple decodable text content field.

## Error Handling

Add service-specific internal errors for predictable caller behavior.

Expected failure cases:

- Meeting not found
- Transcript missing
- Transcript contains no usable exported body text
- Required settings missing
- Base URL invalid
- Request encoding fails
- Network transport fails
- Non-2xx HTTP response
- Response JSON is malformed
- Response does not contain usable assistant text

Error descriptions should stay user-readable because UI will eventually surface them.

For non-2xx responses:

- Include the HTTP status code
- Include a short response body snippet when it can be decoded as text

For replacement flow:

- If confirmation is dismissed, treat it as a no-op, not an error
- If regeneration fails after confirmation, preserve the existing stored summary
- If saving the new summary fails, report the persistence error and preserve the previously stored summary in the UI until a successful reload shows otherwise

## Testing

Follow targeted red-green coverage for the new behavior.

Add tests for:

- Settings store persistence and trimming-aware validation
- Settings view-model load/save behavior
- Transcript body rendering without title/date/duration headers
- Prompt template replacement for `{text}` and `{date}`
- Successful request construction:
  - normalized URL
  - auth header
  - model field
  - rendered prompt body
- Failure when meeting transcript is missing
- Failure when transcript body text is empty
- Failure when any required setting is missing
- Failure when base URL is invalid
- Failure on non-2xx API response
- Failure on malformed or content-less API response
- Success path returning the trimmed summary string
- Meeting summary persistence and replacement in `MeetingStore`
- Clearing stored summary when transcription restarts or completes
- `AppViewModel` generation flow with no existing summary
- `AppViewModel` confirmation flow when a summary already exists
- `AppViewModel` failure path preserving the prior stored summary

Use an injected fake transport so tests stay local and deterministic.

## Implementation Notes

Keep the first version intentionally narrow:

- Do not introduce retry logic yet
- Do not add generic LLM abstractions beyond a small HTTP seam needed for testing

Recommended integration boundaries:

- `MeetingSummaryService` generates text
- `MeetingStore` owns summary persistence
- `MeetingSummarySettingsViewModel` owns settings UI state
- `AppViewModel` owns generation and replacement confirmation
- `MeetingSummaryPane` stays presentation-only

This preserves the current architecture style while connecting the feature end to end.
