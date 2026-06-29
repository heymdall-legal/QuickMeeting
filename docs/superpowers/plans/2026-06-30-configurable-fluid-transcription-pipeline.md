# Configurable Fluid Transcription Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional glossary, CTC vocabulary assistance, LLM correction, and transcript metadata while keeping the existing Parakeet TDT v3 batch path as the default.

**Architecture:** Extend the existing injectable `FluidAudioTranscribing` boundary with pipeline options and metadata. Persist raw/current/corrected transcript layers as optional JSON data on `Meeting`, and keep existing speaker/segment relationships as the UI-visible transcript. Store glossary and pipeline settings in `UserDefaults`.

**Tech Stack:** Swift, SwiftData, SwiftUI, FluidAudio, Swift Testing, OpenAI-compatible chat completions.

---

## File Map

- `QuickMeeting/Models/StoredTranscript.swift`: add pipeline metadata and correction helper models.
- `QuickMeeting/Models/Meeting.swift`: add optional JSON-backed raw/corrected/metadata fields and update transcription lifecycle.
- `QuickMeeting/Services/MeetingStore.swift`: accept pipeline record data when completing transcription.
- `QuickMeeting/Services/Transcription/TranscriptionSettingsStore.swift`: expand settings and add glossary store.
- `QuickMeeting/ViewModels/TranscriptionSettingsViewModel.swift`: expose CTC, correction, and glossary controls.
- `QuickMeeting/Services/Transcription/FluidTranscriptionService.swift`: read options/glossary, run optional correction, and persist metadata.
- `QuickMeeting/Services/Summary/MeetingSummarySettingsStore.swift`: split summary and correction models/prompts while sharing endpoint/auth.
- `QuickMeeting/Services/Summary/MeetingSummaryService.swift`: adapt to new summary settings shape.
- `QuickMeeting/ViewModels/MeetingSummarySettingsViewModel.swift`: expose separate summary model/prompt and correction model/prompt.
- `QuickMeeting/Views/Settings/QMSettingsSheet.swift`: add settings controls and glossary management.
- `QuickMeeting/Views/MeetingDetailView.swift`: offer glossary addition after transcript edits.
- `QuickMeetingTests/*`: add focused tests for persistence, settings, glossary, service forwarding, and correction fallback.

## Tasks

- [ ] Add failing tests for settings, glossary, and transcript layer persistence.
- [ ] Implement settings, glossary, and JSON-backed transcript layer models.
- [ ] Add failing tests for pipeline option forwarding and metadata.
- [ ] Extend `FluidTranscriptionService` and `FluidAudioTranscribing`.
- [ ] Add optional LLM correction service using shared endpoint/auth and distinct correction model/prompt.
- [ ] Add settings UI and transcript edit glossary suggestion UI.
- [ ] Run targeted tests with quiet output.
- [ ] Run a focused build/test verification command before reporting completion.
