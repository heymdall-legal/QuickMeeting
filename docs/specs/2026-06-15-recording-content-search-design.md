# Recording Content Search Design

**Date:** 2026-06-15
**Status:** Approved

## Problem

The recordings search field in `AppSidebarView` currently filters meetings only by title. Users also need to find recordings from a phrase spoken during the meeting or from a user-assigned transcript speaker name.

## Search Behavior

The sidebar will filter meetings using one normalized query:

- Trim leading and trailing whitespace.
- Treat an empty or whitespace-only query as no filter.
- Match the complete normalized query as a contiguous substring.
- Compare case-insensitively.

A meeting matches when the query appears in at least one of:

1. The meeting title.
2. A user-named transcript speaker's display name.
3. The text of any transcript segment.

The query is not split into words. For example, `design review` matches `The design review went well`, but does not match a meeting where `design` and `review` occur separately.

## Speaker Rules

Speaker-name search uses the transcript speakers stored on the meeting.

- User-assigned names such as `Masha Ivanova` are searchable.
- Placeholder or unnamed labels such as `Speaker 1` are excluded using the existing `QMSpeakerPalette.isUnnamed` rule.
- Calendar attendee names in `meeting.attendeeNames` are not searched.

Transcript text remains searchable regardless of which speaker owns a segment.

## Architecture

Extract the filtering predicate from `AppSidebarView` into a small pure helper that accepts a `Meeting` and query string. The sidebar's `filteredMeetings` property will use this helper while preserving the existing grouping and ordering behavior.

The helper will read the meeting's existing title and stored transcript data directly. No persisted search index or model migration is required. This keeps search results current after title changes, speaker renames, or transcription completion.

## Error And Missing-Data Handling

- Meetings without a transcript can still match by title.
- Meetings without named transcript speakers can still match by title or transcript text.
- Missing transcript data does not produce an error; it simply contributes no searchable speaker names or segment text.

## Testing

Focused unit tests will verify:

- Empty and whitespace-only queries return all supplied meetings.
- Title matching is case-insensitive and uses a contiguous substring.
- A named transcript speaker can match a meeting.
- Placeholder speaker names cannot match a meeting.
- Calendar attendee names cannot match a meeting.
- Transcript segment text can match a meeting.
- Multi-word queries do not match when their words are separated or distributed across different fields or segments.
- Meetings without transcripts continue to search safely by title.

## Out Of Scope

- Fuzzy matching, stemming, tokenized all-word matching, or typo tolerance.
- Search-result highlighting or transcript navigation to the matching phrase.
- Searching calendar attendees.
- Persisting or maintaining a full-text search index.
- Changing the recordings list grouping, ordering, or empty-state presentation.
