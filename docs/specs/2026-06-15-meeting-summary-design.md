# Meeting Summary Design

## Goal

Add internal summarization logic that can generate a meeting summary from an existing transcript by calling an OpenAI-compatible `chat/completions` API.

This iteration does not add any UI. It builds the service, settings persistence, prompt rendering, and tests that later UI can depend on.

## Scope

In scope:

- Persist summarization settings needed by the future settings UI
- Validate that a meeting has transcript content before summarization starts
- Render a prompt template with `{text}` and `{date}` placeholders
- Call an OpenAI-compatible API with a configured base URL, auth token, and model name
- Return the generated summary text to the caller
- Cover the behavior with targeted tests

Out of scope:

- Any settings UI
- Any meeting detail UI or action wiring
- Persisting summaries back onto meetings
- Streaming responses
- Additional model parameters such as temperature, top-p, or max tokens

## User Settings

Add a new `MeetingSummarySettingsStore` backed by `UserDefaults`.

Persisted values:

- `baseURL`
- `authToken`
- `modelName`
- `promptTemplate`

Behavior:

- Reads return the raw persisted strings for future UI binding.
- The service uses a validated read path that trims whitespace and treats empty values as missing.
- Missing settings fail fast before any network request is built.

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

Add a new internal `MeetingSummaryService` with an async entry point:

```swift
func summarize(meetingID: UUID) async throws -> String
```

Responsibilities:

- Load the meeting from `MeetingStore`
- Verify a transcript exists and contains usable content
- Load and validate summarization settings
- Render prompt template values
- Build and send the OpenAI-compatible request
- Parse the response and return summary text

Dependencies:

- `MeetingStore`
- `MeetingSummarySettingsStore`
- A small injectable HTTP transport seam for testing
- Date formatting and JSON encoding/decoding helpers kept private to the service module

This keeps meeting lookup, settings, transcript rendering, and network transport separated so later UI can call one focused service without owning the low-level work.

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

## Testing

Follow targeted red-green coverage for the new behavior.

Add tests for:

- Settings store persistence and trimming-aware validation
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

Use an injected fake transport so tests stay local and deterministic.

## Implementation Notes

Keep the first version intentionally narrow:

- Do not persist generated summaries yet
- Do not modify `Meeting` schema yet
- Do not introduce retry logic yet
- Do not add generic LLM abstractions beyond a small HTTP seam needed for testing

This gives the next UI step a stable service contract without prematurely freezing broader AI architecture decisions.
