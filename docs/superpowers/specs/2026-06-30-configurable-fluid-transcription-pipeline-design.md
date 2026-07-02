# Configurable Fluid Transcription Pipeline Design

## Goal

Keep the current stable FluidAudio batch transcription path on Parakeet TDT v3, then add optional glossary, CTC vocabulary assistance, LLM post-correction, and per-job metadata without changing the default behavior.

## Current State

QuickMeeting runs one in-process batch pipeline:

1. Decode and resample the meeting audio with FluidAudio `AudioConverter`.
2. Transcribe with `AsrManager` using Parakeet TDT v3.
3. Run offline diarization over the same samples.
4. Match diarized speaker centroids against known speakers.
5. Persist the final speaker/segment transcript directly on `Meeting`.

The current `FluidAudioTranscribing` abstraction is the right extension point. FluidAudio is pinned to revision `3c6e79f1d74411cae1f3daf50260dd19a585dc2d`. In that revision, public CTC/custom vocabulary building blocks exist (`CustomVocabularyContext`, `CtcModels`, `CtcKeywordSpotter`, `VocabularyRescorer`, `ctcBeamSearch`), but no public `AsrManager.transcribe(... customVocabulary:)` overload is available.

## Design

The new pipeline stays batch-only and staged:

`audio file -> AudioConverter -> Parakeet TDT v3 raw ASR -> optional CTC vocabulary stage -> offline diarization and known-speaker matching -> optional LLM correction -> persist raw transcript, visible transcript, corrected transcript, and metadata`

All new stages are optional. If glossary, CTC, or LLM settings are disabled or incomplete, transcription continues through the existing path.

## Glossary

Glossary terms are stored in `UserDefaults` as JSON. Each term has stable id, text, aliases, weight, enabled state, and timestamps. The store exposes enabled terms as FluidAudio `CustomVocabularyTerm` values when CTC is enabled.

Transcript editing can propose glossary additions after a user changes segment text. The proposal is intentionally non-blocking: the edit is saved first, then the user may add the corrected phrase to the glossary.

## CTC

The app exposes `off`, `auto`, `ctc110m`, and `ctc06b` modes. Today the implementation treats `auto` as `ctc110m`, can load either public `CtcModelVariant`, and records requested/resolved mode in metadata. If model loading or CTC scoring fails, the job falls back to raw ASR and records a warning instead of failing the transcription.

Because Parakeet TDT v3 remains the primary ASR, CTC is used as a post-ASR vocabulary assistance stage over raw TDT text and timings. The abstraction keeps room for a future direct FluidAudio custom vocabulary API.

## LLM Correction

LLM correction reuses the summary endpoint, auth token, and auth header. Summary and correction keep separate model names and prompt templates. Correction is disabled by default.

The default correction prompt instructs the model to fix only transcription errors, punctuation, capitalization, and configured glossary terms. It explicitly forbids changing meaning or adding facts. If correction settings are incomplete or the request fails, transcription completes with the raw/CTC transcript and metadata warning.

## Persistence

Existing `Meeting.transcriptSpeakers` and `Meeting.transcriptSegments` remain the current UI transcript. New optional JSON data fields store:

- raw transcript from ASR before CTC/LLM correction
- corrected transcript when LLM correction runs
- pipeline metadata for the completed job

This avoids a heavy SwiftData relationship migration and keeps old meetings readable.

## UI

Settings adds:

- expanded transcription controls: language, CTC mode, CTC enablement behavior, LLM correction toggle, correction model/prompt
- glossary management: add, edit, remove, enable/disable terms and aliases
- summary settings keep their own model and prompt while sharing endpoint/auth fields with correction

The transcript editor adds a lightweight glossary suggestion after segment text changes.

## Testing

Tests focus on:

- settings store defaults and persistence
- glossary store CRUD and enabled term export
- raw/current/corrected transcript persistence
- pipeline option forwarding and metadata persistence
- LLM correction fallback when disabled or incomplete
- UI/view-model state for the new settings
