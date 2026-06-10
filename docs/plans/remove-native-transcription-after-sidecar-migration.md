# Remove unused native transcription/diarization code after sidecar migration

## Context

QuickMeeting recently switched transcription **and** diarization from native, on-device
frameworks (WhisperKit for ASR, SpeakerKit for diarization, both from the
`argmax-oss-swift` SPM package) to a **Python sidecar** (`python/main.py`, using
`mlx-whisper` + `pyannote-audio`). The sidecar is the only path wired into the app
(`QuickMeetingApp.swift:43` constructs `SidecarTranscriptionService`).

The old native implementation, its model-download management UI, and the old
file-based `transcript.json`/`transcript.md` artifact handling are all still in the
repo as **dead/unreachable code**. The sidecar stores results directly into SwiftData
(`meetingStore.completeTranscription(meetingID:transcript:…)` →
`PersistedTranscriptSpeaker`/`PersistedTranscriptSegment`); it never reads or writes
`transcript.json`. The goal is to delete all of this dead code and drop the now-unused
native SPM dependency, leaving only the sidecar path.

**Key facts that make this safe (verified):**
- The project uses **Xcode 16 file-system-synchronized folder groups**
  (`PBXFileSystemSynchronizedRootGroup`), with **no per-file references** in
  `project.pbxproj`. Deleting a `.swift` file requires **no** project-file edits.
  Only removing the SPM package (Step 4) needs `project.pbxproj` edits.
- The live "rename speaker" flow (`AppViewModel.renameSpeaker` →
  `MeetingTranscriptStore.renameSpeaker(…in: meetingID)` → `MeetingStore.renameSpeaker`)
  is SwiftData-based. The file-based `renameSpeaker(…in: meetingFolderURL:)` variant is dead.
- Every production `completeTranscription` call uses the `transcript:` (SwiftData)
  overload. The `transcriptFileURL:`/`transcriptFilePath:` overloads have no live caller.

The steps below are ordered so each can be executed and verified independently by a
simple subagent. After Steps 1–3 there are zero remaining imports of
`WhisperKit`/`SpeakerKit`/`ArgmaxCore`, which is the precondition for Step 4.

Decisions confirmed with the user: **remove** the orphaned `Meeting.transcriptFilePath`
column (accept SwiftData lightweight migration), and **remove the entire**
`TranscriptionArtifactWriter` (both the dead `transcript.json` and `transcript.md` writing).

---

## Step 1 — Remove native transcription & diarization engine code

**Delete entire files** (`QuickMeeting/Services/Transcription/`):
- `WhisperKitTranscriptionBackend.swift`
- `WhisperTranscriptionBackend.swift` (defines `TranscriptionRequest`, `WhisperTranscriptionBackend`)
- `TranscriptDiarizing.swift` (defines `DefaultTranscriptDiarizer`, `SpeakerKitDiarizationPerformer`, audio loader)

**Delete test files** (`QuickMeetingTests/`):
- `WhisperKitTranscriptionBackendTests.swift`
- `TranscriptDiarizerTests.swift`
- `TranscriptionServiceTests.swift`

**Edit `QuickMeeting/Services/Transcription/TranscriptionService.swift`:**
This file mixes dead code with **types the sidecar still needs**. Remove only the
`final class TranscriptionService` (lines ~34–152, the WhisperKit/diarizer orchestrator,
including its `diarizationSimulationTask` simulation). **Keep** in the file:
- `enum TranscriptionServiceError` — but drop the now-unused `.noInstalledDefaultModel`
  case (it is only thrown by the deleted class).
- `protocol TranscriptionServicing` — `SidecarTranscriptionService` conforms to it.
- `final class NoopTranscriptionService` — used as `AppViewModel`'s default fallback
  (`AppViewModel.swift:54`).

**Edit `QuickMeeting/Models/TranscriptSegment.swift`:** remove the
`struct TranscriptionResult` (only consumed by the deleted native backend/diarizer).
Keep `struct TranscriptSegment` (used everywhere).

**Verify:** `git grep -n "WhisperKit\|SpeakerKit\|TranscriptionResult\|WhisperTranscriptionBackend\|TranscriptDiarizing\|DefaultTranscriptDiarizer"` returns only matches inside `ArgmaxWhisperModelStore.swift` and the model-management files (removed in Step 2) — nothing else.

---

## Step 2 — Remove model-download management & its Settings UI

The downloadable WhisperKit CoreML models are only consumed by the deleted native path;
the sidecar manages its own models in Python. Remove the whole model-management stack.

**Delete entire files:**
- `QuickMeeting/Services/Transcription/ArgmaxWhisperModelStore.swift` (defines `WhisperModelStore`)
- `QuickMeeting/Services/Transcription/ModelSettingsStore.swift`
- `QuickMeeting/Services/Transcription/TranscriptionModelCatalog.swift`
- `QuickMeeting/Services/Transcription/TranscriptionModelManager.swift` (defines `TranscriptionModelManaging`)
- `QuickMeeting/Models/TranscriptionModel.swift` (defines `TranscriptionModel`, `TranscriptionModelID`)
- `QuickMeeting/ViewModels/ModelsSettingsViewModel.swift`
- `QuickMeeting/Views/Settings/ModelsSettingsView.swift` (defines `ModelsSettingsView`, `ModelsSettingsContent`)

**Delete test files:**
- `ModelSettingsStoreTests.swift`
- `ModelsSettingsViewModelTests.swift`
- `TranscriptionModelCatalogTests.swift`
- `TranscriptionModelManagerTests.swift`

**Edit `QuickMeeting/QuickMeetingApp.swift`:** remove the now-dangling wiring —
local `modelSettingsStore`, `modelStore`, `transcriptionModelManager`, the
`@StateObject modelsSettingsViewModel` property and its initialization (lines ~16, 40–41,
57–60, 86–88), and stop passing `modelsViewModel:` into `ContentView` and `SettingsView`.

**Edit `QuickMeeting/Views/Settings/SettingsView.swift`:** remove the `modelsViewModel`
property, the `"Transcription Models"` `Section` + `ModelsSettingsContent`, the
`@State pendingDeleteModelID`, the model-error `.alert`, and the delete `.confirmationDialog`.
Leave the Calendar and Auto Recording sections intact.

**Edit `QuickMeeting/ContentView.swift`:** remove the `modelsViewModel` parameter/property
and the `previewModelsSettingsViewModel()` preview helper (and its use in `#Preview`).

**Verify:** `git grep -n "Models\(Settings\|ViewModel\)\|TranscriptionModel\|WhisperModelStore\|ModelSettingsStore"` returns no hits across `QuickMeeting/` and `QuickMeetingTests/`.

---

## Step 3 — Remove dead `transcript.json` / `transcript.md` file handling

**Delete entire file:**
- `QuickMeeting/Services/Transcription/TranscriptionArtifactWriter.swift`
  (defines `TranscriptionArtifactWriter`, `TranscriptionArtifacts`)

**Delete test files:**
- `TranscriptionArtifactWriterTests.swift`
- `TranscriptMarkdownRenderingTests.swift`

**Edit `QuickMeeting/Services/Transcription/MeetingTranscriptStore.swift`:** keep only the
SwiftData-backed path. Remove:
- the `artifactWriter` stored property + its init parameter,
- `func loadTranscript(in meetingFolderURL: URL)`,
- `func renameSpeaker(id:to:in meetingFolderURL: URL)` and its declaration in the
  `MeetingTranscriptStoring` protocol,
- the now-unused `decoder` if it becomes unused.

Keep `loadTranscript(meetingID:)`, `renameSpeaker(id:to:in meetingID:)`, and the protocol's
`meetingID` method (these back the live UI flow).

**Edit `QuickMeeting/Models/Meeting.swift`:** remove the file-based transcript plumbing:
- the `transcriptFilePath` stored property (line 23), its `init` parameter/assignment, and
  the `transcriptFilePath = nil` lines in `beginTranscription()` and the kept
  `completeTranscription(transcript:…)`,
- the entire `completeTranscription(transcriptFilePath:transcriptPreview:…)` overload (lines ~120–129).

**Edit `QuickMeeting/Services/MeetingStore.swift`:** remove the
`completeTranscription(meetingID:transcriptFileURL:transcriptPreview:…)` overload (lines ~123–136);
keep the `transcript:` overload.

**Note on SwiftData migration:** dropping the optional `transcriptFilePath` attribute is a
safe automatic lightweight migration — no `VersionedSchema`/`MigrationPlan` is required.
The schema in `QuickMeetingApp.swift` (`Schema([Meeting.self, …])`) is unchanged otherwise.

**Verify:** `git grep -n "transcriptFilePath\|transcriptFileURL\|TranscriptionArtifactWriter\|loadTranscript(in\|writeArtifacts\|transcript\.md"` returns no hits. Confirm no remaining caller of the removed `completeTranscription` overloads (the existing tests at `MeetingStoreTests`/`MeetingTranscriptContentTests` already use the `transcript:` overload — leave them).

---

## Step 4 — Drop the unused `argmax-oss-swift` SPM dependency

Only after Steps 1–3 (no remaining `import WhisperKit`/`SpeakerKit`/`ArgmaxCore`).

**Edit `QuickMeeting.xcodeproj/project.pbxproj`** — remove all entries for the package and
its two products (`WhisperKit`, `SpeakerKit`), identifiable by these ids/markers:
- the two `PBXBuildFile` lines `… SpeakerKit in Frameworks` / `… WhisperKit in Frameworks` (~lines 10–11),
- both entries in the `PBXFrameworksBuildPhase` `files` list (~lines 49–50),
- the two `XCSwiftPackageProductDependency` references in the target's
  `packageProductDependencies` (~lines 103–104) and their definitions (~lines 517–526),
- the `XCRemoteSwiftPackageReference "argmax-oss-swift"` entry in the project's
  `packageReferences` (~line 162) and its definition block (~lines 505–514).

**Edit `QuickMeeting.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`:**
remove the `argmax-oss-swift` pin (and any pins that become orphaned, e.g. transitive ones
only that package required — verify nothing else references them).

**Verify:** `git grep -n "argmax\|WhisperKit\|SpeakerKit\|ArgmaxCore" -- '*.pbxproj' 'Package.resolved'` returns nothing.

---

## Verification (end-to-end)

1. **Resolve & build:**
   `xcodebuild -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' build`
   — must succeed with the package removed (Xcode re-resolves SPM on build).
2. **Run the full test suite:**
   `xcodebuild -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' test`
   — all remaining tests pass; the deleted tests are gone, not skipped.
3. **Smoke-test the app** (sidecar path is the only one left):
   - Record a short meeting, run transcription, confirm progress (download → transcribing →
     diarization) and that segments/speakers appear and persist (relaunch the app).
   - Rename a speaker and confirm it persists (exercises the kept SwiftData rename path).
   - Open **Settings** and confirm only **Calendar Integration** and **Auto Recording**
     sections remain (no "Transcription Models" section, no crash).
4. **Final dead-code sweep:**
   `git grep -niE "whisperkit|speakerkit|argmax|transcriptionmodel|artifactwriter|transcriptfilepath|transcript\.(json|md)"`
   — only expected references remain (e.g. comments, the `python/` sidecar, or the
     `transcript.json` literal if any intentionally remains; there should be none in Swift).
