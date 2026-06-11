# Known Speaker Integration Design

## Goal

Integrate the sidecar's known-speaker recognition into the app so meetings can learn speaker identities over time, automatically reuse them in future transcriptions, and keep meeting-local transcript edits independent from the global known-speaker list.

## Context

- `python/main.py` already accepts `--known-speakers-file`.
- The sidecar completed payload already returns per-speaker `matched_id`, `probability`, and `centroid`.
- The app currently stores transcript speakers only as meeting-local `id` and `displayName`.
- Earlier design and plan documents exist around speaker-bank recognition, but this spec is the source of truth for the implementation of the current app-side integration.

## Product Behavior

- Each meeting stores the centroids returned by the transcription sidecar for its diarized speakers.
- The app maintains a global known-speaker list outside individual meetings.
- Each known speaker stores:
  - Stable ID
  - Display name
  - Up to 3 centroids
- When the user manually renames a transcript speaker and that meeting speaker has an associated centroid, the app enrolls that centroid into the global known-speaker list.
- Manual enrollment resolves existing known speakers by exact name match after trimming whitespace and comparing case-insensitively.
- If no exact-name match exists, the app creates a new known speaker.
- When a known speaker already has 3 centroids and a new centroid is added, the oldest centroid is removed.
- On future transcription runs, the app exports the current global known-speaker list to a temporary JSON file and passes that file path to the sidecar.
- If the sidecar returns `matched_id` and `probability > 0.8` for a diarized speaker, the app automatically applies the matched known speaker's display name to that meeting speaker.
- When an auto-match is accepted, the returned centroid from that meeting speaker is also appended to the matched known speaker, again respecting the 3-centroid cap.
- If the user manually enters a name that already exists in the global known-speaker list by exact-name match, the meeting speaker's centroid is appended to that existing known speaker.
- If a speaker was auto-matched and the user later renames that speaker to a different name, the meeting rename wins locally and the app enrolls the centroid under the newly typed name as a separate known speaker if needed.

## Non-Goals

- No dedicated UI to browse, rename, merge, or delete known speakers in this version.
- No fuzzy matching or approximate name merging in enrollment.
- No retroactive relabeling of old meetings after known speakers change.
- No global rename propagation into existing stored meeting transcripts.
- No attempt to reuse or extend older implementation plans for this feature; a new plan should be written from this spec.

## Architecture

The design keeps two persistence layers with a narrow integration boundary.

### Meeting-Local Transcript Layer

Meetings remain the source of truth for what the user sees in a single transcript. Each `TranscriptSpeaker` should be extended to store:

- Meeting-local speaker ID
- Current display name
- Label source: `generic`, `userAssigned`, or `bankMatched`
- Optional matched known-speaker ID
- Optional centroid captured from the sidecar

Transcript segments continue pointing only to meeting-local speaker IDs.

This preserves a stable transcript snapshot even if the global known-speaker list changes later.

### Global Known-Speaker Layer

Known speakers live in the same SwiftData container as meetings, but as separate models.

Each known speaker stores:

- Stable ID
- Display name
- Created and updated timestamps
- Ordered centroid history

Each centroid record stores:

- Centroid vector
- Creation timestamp
- Optional source meeting ID
- Optional source meeting speaker ID

The centroid history is append-only until pruning is needed. When a fourth centroid is added, the oldest centroid is deleted so the newest three remain.

## Components

### `KnownSpeakerStore`

Owns SwiftData persistence for global known speakers and their centroid history.

Responsibilities:

- Load all known speakers for sidecar export
- Find known speaker by exact trimmed case-insensitive display name
- Find known speaker by ID
- Create known speaker
- Append centroid and prune oldest if count exceeds 3
- Support future rename and delete operations without requiring UI now

### `KnownSpeakerJSONWriter`

Builds the temporary JSON file passed to the sidecar.

JSON format:

```json
[
  {
    "id": "known-speaker-id",
    "centroids": [
      [0.1, 0.2, 0.3],
      [0.4, 0.5, 0.6]
    ]
  }
]
```

Only known speakers with at least one centroid should be included.

### `SpeakerRecognitionMapper`

Transforms the sidecar completed payload into enriched meeting-local transcript speakers.

Responsibilities:

- Build transcript speakers using the sidecar `speakers` payload instead of only segment ordering
- Apply matched known-speaker names only when `matched_id` is present and `probability > 0.8`
- Set `labelSource` to `bankMatched` for accepted matches
- Set `labelSource` to `generic` when no accepted match exists
- Preserve the sidecar centroid on the meeting-local speaker for later enrollment

### `KnownSpeakerEnrollmentService`

Handles best-effort learning after a manual speaker rename or an accepted automatic match.

Responsibilities:

- Ignore blank or whitespace-only names
- Ignore meeting speakers without centroid data
- Resolve exact-name matches against the global known-speaker store
- Create a new known speaker when no exact-name match exists
- Append centroid and prune oldest if needed
- Avoid blocking rename persistence or transcript completion if enrollment fails

## Runtime Flow

### Transcription Flow

1. Load the meeting and prepare audio as today.
2. Load global known speakers from `KnownSpeakerStore`.
3. If there is at least one known speaker with at least one centroid, write a temporary JSON file with `KnownSpeakerJSONWriter`.
4. Pass `--known-speakers-file <path>` to `python/main.py`.
5. Run the sidecar and decode the completed payload.
6. Build transcript speakers from the sidecar speaker payload through `SpeakerRecognitionMapper`.
7. For accepted matches, resolve `matched_id` back to the current known-speaker display name and apply it to the meeting-local transcript speaker.
8. Persist the completed transcript, including label source, optional matched known-speaker ID, and optional centroid on each meeting speaker.
9. For each accepted auto-match, best-effort append the returned centroid to the matched known speaker.
10. Clean up the temporary known-speakers JSON file.

If there are no known speakers, transcription runs exactly as it does today except that centroids are still persisted on meeting-local speakers if present.

### Manual Rename Flow

1. User edits a meeting speaker name.
2. The app persists the meeting-local rename immediately.
3. The renamed meeting speaker is marked as `userAssigned`.
4. Any previous `matchedKnownSpeakerID` on that meeting speaker is cleared unless the final typed name exactly matches that same known speaker's current display name.
5. If the final typed name is blank after trimming, no enrollment occurs.
6. If the meeting speaker has a centroid, `KnownSpeakerEnrollmentService` runs as a best-effort follow-up.
7. The service either reuses an exact-name known speaker or creates a new one, then appends the centroid with oldest-first pruning.

Manual rename is always the source of truth for the current meeting, even when the speaker was previously auto-matched.

## Matching Rules

- Accept an automatic match only when:
  - `matched_id` is non-nil
  - `probability` is non-nil
  - `probability > 0.8`
- If any of those checks fail, keep the generic meeting speaker name.
- Exact-name reuse for enrollment means:
  - Trim whitespace and newlines
  - Compare case-insensitively
  - No fuzzy matching

## Persistence Decisions

- Known speakers share the app's existing SwiftData container with meetings.
- Meeting-local transcript data and global known-speaker data remain separate model families.
- Stored meetings should not be mutated later just because a known speaker is renamed or deleted.
- The app should support future known-speaker rename and delete actions by keeping stable IDs and a separate global store now.

## Error Handling

- If known-speaker export fails before transcription starts, log the failure and run the sidecar without `--known-speakers-file`.
- If the sidecar returns malformed speaker metadata for a speaker, fall back to a generic meeting-local speaker label for that speaker.
- If resolving a `matched_id` to a known speaker fails, keep the generic meeting-local speaker label.
- If appending a centroid after an accepted automatic match fails, still save the matched transcript.
- If manual enrollment fails after rename, keep the meeting rename and do not roll it back.
- If a centroid is missing from the sidecar payload, skip enrollment for that speaker.

The feature should prefer false negatives over false positives. Automatic recognition is opportunistic; transcription and rename flows must remain reliable without it.

## Testing

### Unit Tests

- Exact-name known-speaker reuse with case-insensitive comparison
- New known-speaker creation when no exact-name match exists
- Oldest-centroid pruning when adding a fourth centroid
- Recognition mapping when `matched_id` and `probability > 0.8` are present
- Fallback to generic speaker labels when probability is too low or metadata is missing
- Manual rename converting a meeting speaker to `userAssigned`
- Manual rename clearing stale matched known-speaker IDs when the typed name changes
- Enrollment skipping blank names or missing centroids

### Integration Tests

- Sidecar service passes `--known-speakers-file` only when export data exists
- Completed transcription persists speaker metadata including label source, matched known-speaker ID, and centroid
- Accepted automatic matches apply the current known-speaker display name to the meeting transcript
- Manual rename persists even if known-speaker enrollment fails afterward

## Future Compatibility

This design intentionally prepares for later known-speaker management UI.

Future actions should be possible without redesigning storage:

- Rename known speaker globally
- Delete known speaker globally
- Show known speaker centroid count
- Show which meetings contributed centroids

Those capabilities are out of scope for this implementation, but the data model should not block them.
