# Speaker Bank Recognition Design

## Goal

Add a global bank of known speakers that can learn from manual speaker renames and later auto-label diarized speakers in new recordings when there is a high-confidence match.

## Product Behavior

- After transcription and diarization, meetings still start with meeting-local speakers.
- The app runs a recognition pass against a global speaker bank before finalizing the transcript.
- If a meeting speaker strongly matches a known person, the app replaces the generic `Speaker N` label with that person's saved name.
- If confidence is not high enough, the app preserves the generic label.
- When a user manually renames a speaker to a non-empty name, the app automatically uses that rename as an enrollment signal for the global speaker bank.
- If the renamed value matches an existing bank person by case-insensitive exact-name match, the app updates that person.
- Otherwise, the app creates a new bank person.
- No dedicated speaker-bank UI is included in this version.

## Scope

- Add a persistent global speaker bank for cross-recording recognition.
- Add recognition as a post-diarization step in the transcription pipeline.
- Add automatic enrollment from manual speaker renames.
- Store multiple embeddings per known person, with caps and quality filtering.
- Extend transcript speaker metadata so the app can tell whether a label is generic, user-assigned, or bank-matched.
- Keep the feature resilient so transcription and rename flows still succeed when bank operations fail.

## Non-Goals

- No dedicated UI to browse, merge, rename, or delete bank entries.
- No fuzzy person-name merging beyond case-insensitive exact-name reuse.
- No attempt to make recognition part of diarization itself.
- No retroactive relabeling of old meetings outside the current meeting flow.
- No cross-device sync for the speaker bank.

## Architecture

The design introduces a new speaker-recognition layer on top of the existing meeting-local transcript model.

### Meeting-Local Transcript Layer

Meeting transcripts remain self-contained artifacts with meeting-scoped speakers and segments. The transcript speaker model should be extended so each speaker keeps:

- Stable meeting-local `speakerID`
- Current `displayName`
- Label provenance such as `generic`, `userAssigned`, or `bankMatched`
- Optional matched bank person ID when the display name came from recognition

Segments should continue pointing to meeting-local speaker IDs rather than global person IDs.

### Global Speaker Bank Layer

The speaker bank is a separate persistent store of known people. Each bank person should contain:

- Stable bank person ID
- Canonical display name
- Created and updated timestamps
- A capped collection of stored voice embeddings

Each stored embedding should also keep lightweight metadata:

- Source meeting ID
- Source meeting speaker ID
- Source segment duration or sampled duration
- Creation timestamp

This separation keeps transcript rendering simple and prevents global identity changes from mutating stored meeting artifacts unintentionally.

## Runtime Flow

### Transcription Flow

1. Transcribe meeting audio as today.
2. Diarize the transcript into meeting-local speakers as today.
3. Group eligible audio by meeting-local speaker.
4. Build comparison embeddings for each meeting speaker from trimmed, quality-filtered audio segments.
5. Compare each meeting speaker against the global speaker bank.
6. If the best match clears a strict confidence threshold and beats the second-best candidate by a minimum margin, set that transcript speaker's `displayName` to the bank person's name and mark it as `bankMatched`.
7. If no strong match exists, keep the existing generic label.
8. Save the finalized transcript.

### Manual Rename Flow

1. User renames a meeting speaker.
2. Persist the transcript rename through the existing meeting transcript store.
3. Mark that meeting speaker as `userAssigned`.
4. As a best-effort follow-up step, resolve or create a bank person using case-insensitive exact-name matching.
5. Extract eligible audio for the renamed meeting speaker.
6. Generate and store new embeddings for that bank person, respecting quality rules and per-person caps.

Rename persistence remains the source of truth for the current meeting. Bank enrollment must not block or roll back a successful rename.

## Segment Hygiene

Diarization boundaries are noisy, especially when one speaker's final words spill into the next speaker span. The bank layer should avoid using raw diarization spans directly for embeddings.

### Cropping Rule

- Only consider segments above a minimum duration threshold.
- Trim a safety margin from the start and end of each candidate segment before embedding.
- Use an adaptive trim so shorter segments are not over-cropped.
- Skip any segment whose trimmed core becomes too short to be useful.

### Why This Applies Everywhere

The same cropped-core rule should be used for:

- Enrollment after manual rename
- Recognition during transcription

This reduces contamination from speaker handoff errors both when writing to the bank and when matching against it.

## Enrollment Strategy

Use multiple embeddings per person rather than a single canonical embedding.

### Recommended Rules

- Filter out short or poor candidate segments.
- Prefer longer, cleaner segments.
- Store a small capped set such as 3 to 5 embeddings per person.
- Prefer diversity across meetings when adding new samples to an existing person.
- When the cap is exceeded, drop the lowest-value or oldest samples according to a deterministic rule.

This gives better cross-recording robustness than a single sample while keeping storage and matching costs small and predictable.

## Matching Rules

- Recognition should only auto-apply labels for very strong matches.
- The best score must meet a minimum confidence threshold.
- The best score must exceed the second-best score by a minimum margin.
- If either condition fails, keep the generic speaker label.
- User-assigned speaker names always override automated recognition within the same meeting.

## Persistence Design

The transcript and the bank should remain separate stores with a narrow integration boundary.

### Transcript Changes

Extend persisted transcript speaker records to include:

- Label provenance
- Optional matched bank person ID

Meeting-local speaker IDs and transcript segments remain unchanged.

### Bank Storage

Add a new persistent store for:

- Known speaker persons
- Stored voice embeddings and their metadata

This store should be isolated behind a dedicated service or actor rather than accessed directly from UI code or the transcription view model.

## Service Boundaries

Introduce a focused speaker-recognition subsystem with clear responsibilities.

### Proposed Responsibilities

- `SpeakerBankStore`: persistence for bank persons and embeddings
- `SpeakerEmbeddingService`: generates embeddings from selected audio spans
- `SpeakerRecognitionService`: compares meeting speakers against the bank and returns high-confidence matches
- `SpeakerEnrollmentService`: handles rename-triggered create-or-update enrollment
- `SpeakerAudioSegmentSelector`: turns diarized speaker segments into trimmed, eligible audio spans

These may be separate types or grouped behind a smaller public facade, but the responsibilities should stay distinct so the code remains testable and easy to change.

## Error Handling

- If the bank is empty, recognition is a no-op.
- If embedding generation fails during transcription, the meeting still completes transcription with generic labels.
- If enrollment fails after rename, the rename still remains saved in the transcript.
- Blank or whitespace-only names should never trigger enrollment.
- If there is not enough usable audio for a speaker, skip enrollment or recognition for that speaker rather than guessing.

## Concurrency

Bank reads and writes should flow through one serialized service or actor.

This avoids races when:

- Multiple renames happen close together
- A transcription recognition pass overlaps with enrollment work
- Per-person embedding caps need deterministic pruning

## Testing

Add focused tests around the new boundaries rather than broad end-to-end-only coverage.

### Unit Tests

- Case-insensitive exact-name reuse for existing bank persons
- New-person creation when no exact name match exists
- Confidence-threshold and second-best-margin matching behavior
- No auto-labeling when confidence is too low
- Enrollment cap and pruning behavior
- Segment trimming and minimum-core filtering
- User-assigned names overriding later automated matches
- Best-effort enrollment failure not affecting rename success

### Integration Tests

- Transcription pipeline applies bank matches when recognition succeeds
- Transcription pipeline preserves generic labels when recognition does not qualify
- Rename flow updates the transcript immediately and triggers enrollment separately

## Rollout Notes

- Start with conservative matching thresholds.
- Prefer false negatives over false positives.
- Keep all bank operations transparent in logs and diagnostics so threshold tuning is possible later.
- Defer speaker-bank management UI until the automatic pipeline proves useful in real recordings.
