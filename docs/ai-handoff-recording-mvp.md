# AI Handoff: Recording MVP

## Workspace

- Repo root: `/Users/heymdall/Developer/QuickMeeting`
- Active implementation worktree: `/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp`
- Active branch in worktree: `codex/recording-mvp`
- Main design doc: [quickmeeting-architecture-design.md](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/docs/quickmeeting-architecture-design.md)
- Active implementation plan: [2026-05-04-recording-mvp.md](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/docs/superpowers/plans/2026-05-04-recording-mvp.md)

## Current Status

Tasks completed from the recording MVP plan:

1. `Task 1`: Meeting domain model and SwiftData persistence
2. `Task 2`: Meeting artifact folders and canonical `audio.wav` paths
3. `Task 3`: `AppViewModel` start flow and recording state
4. `Task 4`: `MeetingStore.finishRecording(...)`
5. `Task 5`: permission abstraction and native permission checks
6. `Task 6`: `AudioCapturePipeline` / `DefaultRecordingService` boundary
7. `Task 7`: real native fallback capture path
8. `Task 8`: main window meeting library UI

Tasks still pending:

9. `Task 9`: menubar start/stop control
10. `Task 10`: final stop-flow integration and end-to-end verification

## What Is Implemented

### Data and persistence

- `Meeting` SwiftData model exists and is the app’s real persisted entity.
- `MeetingStore` can:
  - create meetings
  - delete failed-start meetings
  - finish a recording by mutating the existing model in place
- `MeetingFileStore` creates one folder per meeting and returns a canonical `audio.wav` path.

### Recording state and orchestration

- `AppViewModel` owns recording lifecycle state.
- `startRecording()` currently handles:
  - permission preflight
  - retry from recoverable failed state
  - meeting/artifact creation
  - rollback if recorder startup fails
  - best-effort recorder stop before rollback cleanup
- `stopRecording()` support was added to the shared view model so the window UI can stop an active session.
- Selection logic in the window now follows `AppViewModel`’s active/recoverable meeting source of truth.

### Recording boundary and live capture

- `RecordingService` exists.
- `DefaultRecordingService` wraps `AudioCapturePipeline`.
- `DefaultRecordingService` has already been hardened for:
  - failed pipeline start recovery
  - failed pipeline stop retry
  - reentrant start/stop overlap
  - duplicate stop coalescing

### Native capture path

- `NativeAudioCapturePipeline` now exists behind `AudioCapturePipeline`.
- Important limitation:
  - it currently captures **system audio only**
  - it does **not** mix microphone audio yet
- This is intentional and was accepted under the Task 7 fallback allowed by the plan.
- Current live path:
  - uses audio-only `ScreenCaptureKit`
  - chooses the first shareable display
  - writes canonical 48 kHz stereo WAV through a service-owned writer

### Main window UI

- `ContentView` is now a real meeting-library split view.
- New views:
  - `MeetingListView`
  - `MeetingDetailView`
  - `RecordingToolbarControls`
- Window UI already supports:
  - showing meetings sorted by newest first
  - selecting a meeting
  - viewing basic metadata and audio path
  - starting and stopping recording from the toolbar

## Known Limitations

These are known and acceptable at the current checkpoint:

- No menubar UI yet.
- No final end-to-end stop-flow pass yet.
- Native capture path is **system-audio-only** for now.
- `NativeAudioCapturePipeline` still defers unexpected stream termination until later drain/stop rather than proactively surfacing it immediately.
- Capture target is currently “first shareable display”; no picker or display choice yet.

## Verification State

The work was repeatedly verified with unsigned local Xcode commands such as:

```bash
xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-<task> \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=
```

This unsigned path was necessary because normal signing and some sandboxed Xcode paths were unreliable in the environment.

By the end of Task 8, targeted and full test runs reported success from the worker on the worktree branch.

## Files Most Relevant For The Next Agent

### Core app

- [QuickMeetingApp.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/QuickMeetingApp.swift)
- [ContentView.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/ContentView.swift)
- [AppViewModel.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/ViewModels/AppViewModel.swift)

### Models and persistence

- [Meeting.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/Models/Meeting.swift)
- [MeetingStatus.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/Models/MeetingStatus.swift)
- [RecordingState.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/Models/RecordingState.swift)
- [MeetingStore.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/Services/MeetingStore.swift)
- [MeetingFileStore.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/Services/MeetingFileStore.swift)

### Recording

- [RecordingPermissions.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/Services/Recording/RecordingPermissions.swift)
- [RecordingService.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/Services/Recording/RecordingService.swift)
- [AudioCapturePipeline.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/Services/Recording/AudioCapturePipeline.swift)

### Window UI

- [MeetingListView.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/Views/MeetingListView.swift)
- [MeetingDetailView.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/Views/MeetingDetailView.swift)
- [RecordingToolbarControls.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeeting/Views/RecordingToolbarControls.swift)

### Tests

- [MeetingStoreTests.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeetingTests/MeetingStoreTests.swift)
- [MeetingFileStoreTests.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeetingTests/MeetingFileStoreTests.swift)
- [AppViewModelTests.swift](/Users/heymdall/Developer/QuickMeeting/.worktrees/codex-recording-mvp/QuickMeetingTests/AppViewModelTests.swift)

## Recommended Next Steps

### Task 9

Implement the menubar path:

- add a status item / popover entry point
- share the same `AppViewModel` instance as the window
- expose Start / Stop from the menubar
- verify the menubar and window stay in sync

### Task 10

Finish the stop-flow and do the MVP verification pass:

- ensure stop from all entry points updates persistence cleanly
- ensure the selected meeting and toolbar state stay aligned
- run full unsigned tests again
- do a manual app smoke test if possible

## Important Notes For The Next Agent

- Do not switch back to `master`; continue inside the worktree branch unless told otherwise.
- Do not regress the explicit Task 7 fallback: system-audio-only is currently honest and intentional.
- Be careful with `AppViewModel` selection/state logic; it already went through a review loop to centralize active/recoverable meeting ownership.
- Be careful with `DefaultRecordingService` and `NativeAudioCapturePipeline`; both already went through concurrency and lifecycle review loops, so preserve those invariants when wiring menubar or stop-flow behavior.
