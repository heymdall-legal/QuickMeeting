# QuickMeeting Architecture Design

## Summary

QuickMeeting is a macOS app for recording meeting audio, combining system audio and microphone input into a single recording, transcribing that recording locally with downloadable Whisper models, and storing both audio and transcript artifacts on disk. The primary product shell is a standard windowed SwiftUI app with a companion menubar control for quick start and stop.

The architecture is designed for incremental delivery. The initial foundation fully supports recording, meeting storage, model management, manual transcription, and basic menubar control. Calendar integration, notifications, and transcript auto-export are intentionally modeled as extension services that plug into the same core domain model without changing the recording or transcription pipeline.

## App Structure

### Application Shell

- `QuickMeetingApp` owns app lifecycle, shared stores, and service wiring.
- The main window is the primary interface for the meeting library, meeting detail, settings, and model management.
- A status bar item provides quick `Start Recording` and `Stop Recording` control and reflects current recording state.
- UI components talk only to app-level view models or controllers, never directly to capture APIs or Whisper internals.

### Core Services

- `RecordingService`
  - Starts and stops capture.
  - Enforces a single active recording session.
  - Creates the meeting record at recording start.
  - Coordinates system-audio capture, microphone capture, and final mixed-file output.

- `AudioCapturePipeline`
  - Captures system audio via `ScreenCaptureKit`.
  - Captures microphone audio via native audio input APIs such as `AVAudioEngine`.
  - Normalizes both streams to a shared format for mixing.
  - Produces one canonical master recording per meeting.

- `AudioMixer`
  - Aligns microphone and system streams.
  - Writes one lossless WAV file as the authoritative meeting audio artifact.
  - Keeps mixing isolated from UI and persistence logic.

- `MeetingRepository`
  - Owns creation, updates, queries, and deletion of meeting metadata.
  - Uses SwiftData for indexed metadata and app-visible state.
  - Stores paths and summary metadata in the database, not large blobs.

- `TranscriptionService`
  - Validates model availability.
  - Runs Whisper against the stored WAV file.
  - Writes transcript artifacts to disk.
  - Updates meeting transcription status and preview text.

- `ModelManager`
  - Manages multiple downloaded local models.
  - Tracks installed models, default selection, availability, and storage location.
  - Exposes download progress and failure state to the UI.

### Extension Services

These are additive services that can be introduced later without changing the core recording flow:

- `CalendarIntegrationService`
- `MeetingTitleGenerator`
- `MeetingNotificationService`
- `ExportService`

## Data Model

### Meeting Entity

The core persisted entity is `Meeting` with these fields:

- `id`
- `title`
- `startedAt`
- `endedAt`
- `status`
- `audioFilePath`
- transcript speakers
- transcript segments
- `transcriptPreview` optional
- `duration` optional
- `calendarEventID` optional
- `createdAt`
- `updatedAt`

### Meeting Status

The design uses explicit states rather than inferred UI flags:

- `recording`
- `recorded`
- `transcribing`
- `completed`
- `failed`

The implementation may later split `failed` into more granular error types, but the architecture should preserve failure cause information from the start.

## Storage Model

### Metadata Storage

- SwiftData stores indexed meeting metadata.
- Meeting records are the source of truth for list views, detail views, status, and canonical transcript data.
- Structured transcript data is stored in SwiftData, not in filesystem sidecars.

### File Storage

Each meeting gets its own folder under an app-managed root directory. That folder contains:

- the canonical mixed WAV recording
- optional future derived artifacts such as explicit exports

SwiftData is the indexed catalog for fast library access and transcript data. Disk is used only for the canonical audio recording and future explicit export artifacts.

### Settings Storage

App settings are stored separately from meeting records using `UserDefaults` or a lightweight settings store. Settings include:

- downloaded models and their locations
- default model selection
- auto-export enabled or disabled
- export destination
- selected calendars
- menubar preferences

## Core Workflows

### Start Recording

1. User starts recording from the main window or menubar.
2. App validates screen recording and microphone permissions.
3. `MeetingRepository` creates a new meeting in `recording` state.
4. `RecordingService` starts capture and assigns the meeting folder and output paths.
5. `AudioCapturePipeline` captures system audio and microphone audio in parallel.
6. `AudioMixer` writes one canonical WAV file for the meeting.

### Stop Recording

1. User stops recording from the main window or menubar.
2. `RecordingService` stops both capture inputs cleanly.
3. The mixer finalizes the WAV file.
4. `MeetingRepository` updates `endedAt`, `duration`, `audioFilePath`, and moves the meeting to `recorded`.

### Recording Constraints

- Only one active recording session is allowed at a time.
- The audio file saved for a meeting is always one mixed recording, not separate user-facing microphone and system tracks.
- Permission denial blocks recording start and surfaces a guided recovery path.
- A failed recording should preserve the meeting record when possible for diagnostics and retry UX.

### Manual Transcription

1. User selects a recorded meeting and chooses `Transcribe`.
2. `TranscriptionService` confirms a local model is available.
3. The saved WAV file is passed to Whisper through a transcription backend abstraction.
4. Structured transcript data is stored in SwiftData.
5. Meeting metadata is updated with transcript preview and final status.

### Transcription Design Boundary

- The architecture targets a native macOS app design.
- The Whisper runtime still sits behind an internal protocol boundary so the backend can evolve without changing the UI or meeting repository.
- Recording and transcription are independent jobs, so users can record now and transcribe later.

## UI Structure

### Main Window

The main app window should provide:

- meeting list sorted by date
- meeting detail view
- recording controls
- transcription action
- transcript viewer
- settings entry point
- model management entry point

### Menubar

The status item should provide:

- current recording state indicator
- start recording action when idle
- stop recording action when active
- shortcut into the main app window

The menubar should control the same `RecordingService` instance as the main window, not a separate recording path.

## Future Extensions

### Calendar Title Suggestions

- On recording start, the app may check selected calendars for an event beginning within 5 minutes of the recording start time.
- If a match exists, the meeting title should default to the event title.
- If no match exists, the app should generate a fallback title like `Meeting at 14:00 on 2026-04-22`.

### Notifications

- Future meeting-start notifications should come from calendar-derived events.
- Notifications may offer one-click `Start Recording`.
- A recording-stop notification may offer one-click `Stop Recording`.
- Notification actions must route into the same `RecordingService`.

### Transcript Export

- After transcription completes, `ExportService` may optionally write transcript text to a user-selected location.
- Export is additive and must not replace or relocate the app-managed canonical transcript artifact.
- Export is additive and must not replace the SwiftData-backed canonical transcript data.

## Failure Handling

The architecture should preserve explicit failure handling for:

- permission denial
- capture startup failure
- mixing failure
- model download failure
- transcription failure
- export failure

Rules:

- Audio artifacts are never deleted automatically because a later step failed.
- A failed transcription must not corrupt or remove the source audio.
- Partial or failed work should remain visible in the library with retryable state where possible.
- Error reporting should be user-friendly in UI and detailed enough internally for debugging.

## Public Interfaces And Types

The implementation should preserve these architectural boundaries, even if concrete names evolve:

- `RecordingService`
- `MeetingRepository`
- `TranscriptionService`
- `ModelManager`
- `CalendarIntegrationService`
- `ExportService`

Core types that should remain stable across iterations:

- `Meeting`
- `MeetingStatus`
- `TranscriptionModel`
- `RecordingState`
- `TranscriptionResult`

## Test Scenarios

### Core Flows

- Start recording from the main window creates a meeting and begins capture.
- Start recording from the menubar uses the same recording session state as the main window.
- Stop recording finalizes a single mixed WAV file and updates meeting metadata.
- Transcribe a recorded meeting with an installed model stores transcript text and updates status.
- The meeting list shows recordings with and without transcripts.

### Failure Cases

- Recording start fails when screen recording permission is denied.
- Recording start fails when microphone permission is denied.
- Mixing failure leaves the meeting record intact and marks failure.
- Transcription cannot start when no model is installed.
- Whisper failure preserves the original audio and records an error state.

### Extension Readiness

- Calendar lookup can set the title when a matching event exists.
- Title generation falls back deterministically when no event matches.
- Auto-export writes transcript text only when enabled.

## Assumptions And Defaults

- Canonical saved meeting audio format: lossless WAV
- Metadata backend: SwiftData
- Artifact storage: files on disk
- App shell: window app plus menubar control
- Whisper runtime: local and abstracted behind a service boundary
- Model support: multiple downloaded local models
- Scope: core architecture in detail, advanced features as planned extensions
