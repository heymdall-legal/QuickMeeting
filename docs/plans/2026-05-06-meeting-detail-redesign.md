**Goal:** Rework `MeetingDetailView` so transcript text becomes the primary content area, metadata and actions move into a fixed right sidebar, and audio playback docks to the bottom with a simple empty state for untranscribed meetings.

**Architecture:** Keep the redesign localized to the meeting detail surface by introducing a small transcript-content state helper and reshaping `MeetingDetailView` into a three-region layout. Reuse `MeetingAudioPlayback` and `AppViewModel` behaviors as-is wherever possible so the change remains presentational, with only narrow helper logic added for transcript reading and unavailable-file fallback.

**Tech Stack:** SwiftUI, Foundation, SwiftData, Swift Testing, Xcode

---

## File Structure

- Create: `QuickMeeting/Support/MeetingTranscriptContent.swift`
  - Defines a small view-facing state model and transcript file reader for present, missing, and unreadable transcript cases.
- Create: `QuickMeetingTests/MeetingTranscriptContentTests.swift`
  - Covers transcript loading from file paths and friendly fallback states.
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
  - Replaces the metadata-first scroll view with transcript-first content, fixed right sidebar sections, and a bottom playback bar.
- Modify: `QuickMeeting/ContentView.swift`
  - Updates the preview meeting data so the transcript-first detail preview stays useful after the redesign.
- Reuse: `QuickMeeting/Services/Playback/MeetingAudioPlayback.swift`
  - Keeps playback behavior and state model unchanged unless a tiny read-only convenience property improves the bottom bar.
- Reuse: `QuickMeeting/ViewModels/AppViewModel.swift`
  - Keeps deletion and transcription actions unchanged.
- Reuse: `QuickMeetingTests/MeetingAudioPlaybackTests.swift`
  - Remains the safety net for docked playback behavior.

## Task 1: Add transcript content state and tests

**Files:**
- Create: `QuickMeeting/Support/MeetingTranscriptContent.swift`
- Create: `QuickMeetingTests/MeetingTranscriptContentTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct MeetingTranscriptContentTests {
    @Test
    func missingTranscriptPathReturnsNotAvailable() throws {
        let content = try loadMeetingTranscriptContent(from: nil)

        #expect(content == .notAvailable)
    }

    @Test
    func readableTranscriptFileReturnsText() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let transcriptURL = rootURL.appendingPathComponent("transcript.txt")
        try "Line one\nLine two".write(to: transcriptURL, atomically: true, encoding: .utf8)

        let content = try loadMeetingTranscriptContent(from: transcriptURL.path)

        #expect(content == .text("Line one\nLine two"))
    }

    @Test
    func unreadableTranscriptPathReturnsUnavailable() throws {
        let fileManager = FileManager.default
        let missingPath = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("missing-transcript.txt")
            .path

        let content = try loadMeetingTranscriptContent(from: missingPath)

        #expect(content == .unavailable(message: "Transcript file is unavailable."))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-meeting-detail-plan "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: FAIL with errors that `loadMeetingTranscriptContent` and `MeetingTranscriptContent` do not exist yet.

- [ ] **Step 3: Write the minimal implementation**

`QuickMeeting/Support/MeetingTranscriptContent.swift`

```swift
import Foundation

enum MeetingTranscriptContent: Equatable {
    case text(String)
    case notAvailable
    case unavailable(message: String)
}

func loadMeetingTranscriptContent(
    from transcriptFilePath: String?,
    fileManager: FileManager = .default
) throws -> MeetingTranscriptContent {
    guard let transcriptFilePath else {
        return .notAvailable
    }

    guard fileManager.fileExists(atPath: transcriptFilePath) else {
        return .unavailable(message: "Transcript file is unavailable.")
    }

    do {
        let transcriptText = try String(contentsOfFile: transcriptFilePath, encoding: .utf8)
        return .text(transcriptText)
    } catch {
        return .unavailable(message: "Transcript file is unavailable.")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-meeting-detail-plan "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests
```

Expected: PASS for 3 tests in `MeetingTranscriptContentTests`.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "test: cover meeting transcript content states"
```

## Task 2: Reshape `MeetingDetailView` into transcript-first layout

**Files:**
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Reuse: `QuickMeeting/Support/MeetingTranscriptContent.swift`

- [ ] **Step 1: Write the failing view-facing tests first if the file already has coverage; otherwise codify the state branches inline and verify manually**

Add a focused test only if there is already a stable SwiftUI view-testing pattern in the repo. Otherwise, keep automated coverage in `MeetingTranscriptContentTests` and use manual verification for layout, since the existing test suite is model- and service-heavy rather than snapshot-driven.

- [ ] **Step 2: Replace the stacked scroll layout with the new three-region structure**

`QuickMeeting/Views/MeetingDetailView.swift`

```swift
import SwiftUI

struct MeetingDetailView: View {
    let meeting: Meeting
    let canDelete: Bool
    let canTranscribe: Bool
    let onTranscribe: () -> Void
    let onDelete: () -> Void

    @StateObject private var playback = MeetingAudioPlayback()
    @State private var transcriptContent: MeetingTranscriptContent = .notAvailable
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                transcriptPane

                Divider()

                sidebar
                    .frame(width: 300)
            }

            Divider()

            playbackBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .navigationTitle(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
        .task(id: meeting.id) {
            transcriptContent = (try? loadMeetingTranscriptContent(from: meeting.transcriptFilePath))
                ?? .unavailable(message: "Transcript file is unavailable.")
            try? playback.loadAudioFile(at: URL(fileURLWithPath: meeting.audioFilePath))
        }
        .alert(
            "Delete Meeting?",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the meeting and its recording file from this Mac.")
        }
    }
}
```

- [ ] **Step 3: Add the transcript pane branches**

In `QuickMeeting/Views/MeetingDetailView.swift`, add the main content helpers:

```swift
private var transcriptPane: some View {
    VStack(alignment: .leading, spacing: 16) {
        Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
            .font(.title2.weight(.semibold))

        switch transcriptContent {
        case .text(let transcript):
            ScrollView {
                Text(transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .lineSpacing(6)
            }
        case .notAvailable:
            transcriptEmptyState
        case .unavailable(let message):
            transcriptUnavailableState(message: message)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(24)
}

private var transcriptEmptyState: some View {
    VStack(spacing: 12) {
        Text("Not transcribed yet")
            .font(.title3.weight(.semibold))

        Text("Meeting audio is available and can be transcribed when you're ready.")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        Button("Transcribe", action: onTranscribe)
            .buttonStyle(.borderedProminent)
            .disabled(!canTranscribe)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

private func transcriptUnavailableState(message: String) -> some View {
    VStack(spacing: 12) {
        Text("Transcript unavailable")
            .font(.title3.weight(.semibold))

        Text(message)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        Button("Transcribe", action: onTranscribe)
            .buttonStyle(.borderedProminent)
            .disabled(!canTranscribe)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

- [ ] **Step 4: Add the fixed sidebar sections in the approved order**

In `QuickMeeting/Views/MeetingDetailView.swift`, add:

```swift
private var sidebar: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            detailSection
            actionSection
            filesSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

private var detailSection: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Details")
            .font(.headline)

        LabeledContent("Status", value: statusText)
        LabeledContent(
            "Started",
            value: meeting.startedAt.formatted(.dateTime.month(.wide).day().year().hour().minute())
        )

        if let endedAt = meeting.endedAt {
            LabeledContent(
                "Ended",
                value: endedAt.formatted(.dateTime.month(.wide).day().year().hour().minute())
            )
        }

        if let duration = meeting.duration {
            LabeledContent("Duration", value: durationText(duration))
        }
    }
}

private var actionSection: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Actions")
            .font(.headline)

        Button("Transcribe", action: onTranscribe)
            .buttonStyle(.borderedProminent)
            .disabled(!canTranscribe)

        Button("Delete Meeting", role: .destructive) {
            isShowingDeleteConfirmation = true
        }
        .disabled(!canDelete)
    }
}

private var filesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Files")
            .font(.headline)

        VStack(alignment: .leading, spacing: 6) {
            Text("Audio File")
                .font(.subheadline.weight(.medium))
            Text(meeting.audioFilePath)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        if let transcriptFilePath = meeting.transcriptFilePath {
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcript File")
                    .font(.subheadline.weight(.medium))
                Text(transcriptFilePath)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
```

- [ ] **Step 5: Replace the inline playback block with a docked playback bar**

In `QuickMeeting/Views/MeetingDetailView.swift`, add:

```swift
private var playbackBar: some View {
    HStack(spacing: 16) {
        Button(action: playback.togglePlayback) {
            Image(systemName: playbackButtonSystemImage)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!playback.isPlaybackAvailable)

        Slider(
            value: Binding(
                get: { playback.currentTime },
                set: { playback.seek(to: $0) }
            ),
            in: 0...max(playback.duration, 0.1)
        )
        .disabled(!playback.isPlaybackAvailable)

        Text("\(playback.elapsedTimeText) / \(playback.durationText)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 88, alignment: .trailing)
    }
}
```

- [ ] **Step 6: Run focused tests to protect transcript and playback behavior**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-meeting-detail-plan "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS for transcript-content, playback, and existing app-level action tests.

- [ ] **Step 7: Commit**

```bash
git add QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "feat: redesign meeting detail layout"
```

## Task 3: Keep previews and manual verification aligned with the new experience

**Files:**
- Modify: `QuickMeeting/ContentView.swift`

- [ ] **Step 1: Update preview data to exercise the transcript-first detail view**

In `QuickMeeting/ContentView.swift`, update the preview seed meeting so it includes transcript content:

```swift
let sampleMeeting = Meeting(
    title: "Weekly Product Sync",
    startedAt: Date(timeIntervalSince1970: 1_714_561_200),
    endedAt: Date(timeIntervalSince1970: 1_714_564_800),
    status: .completed,
    audioFilePath: "/Users/preview/Library/Application Support/QuickMeeting/Meetings/sample/audio.wav",
    transcriptFilePath: "/Users/preview/Library/Application Support/QuickMeeting/Meetings/sample/transcript.txt",
    transcriptPreview: "Agenda review and shipping plan alignment.",
    duration: 3_600
)
```

If the preview needs a readable transcript file to render the `.text` branch, either point it at a temporary seeded file in the preview helper or add a dedicated `MeetingDetailView` preview that injects `.text` state locally. Keep the production view path unchanged.

- [ ] **Step 2: Run the full relevant test set**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-meeting-detail-plan "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingTranscriptContentTests -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/MeetingFileStoreTests
```

Expected: PASS for the new transcript helper tests and existing playback, meeting, and app-view-model tests.

- [ ] **Step 3: Manually verify the approved UI behaviors**

Run:

```bash
xcodebuild -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" build
```

Expected: BUILD SUCCEEDED.

Then launch the app and verify:

- a transcribed meeting shows transcript text as the main content
- an untranscribed meeting shows `Not transcribed yet` and an in-content `Transcribe` button
- the right sidebar order is `Details`, `Actions`, `Files`
- `Transcribe` also exists in the sidebar
- the bottom player shows play or pause, a centered slider, and right-aligned time
- delete confirmation still appears
- switching meetings refreshes transcript and playback correctly

- [ ] **Step 4: Commit**

```bash
git add QuickMeeting/ContentView.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "chore: verify meeting detail redesign"
```

## Self-Review

- Spec coverage check:
  - transcript-first main content is covered in Task 2 steps 2 and 3
  - fixed right sidebar with `Details`, `Actions`, `Files` is covered in Task 2 step 4
  - docked playback bar is covered in Task 2 step 5
  - empty state and duplicate `Transcribe` entry points are covered in Task 2 step 3 and Task 2 step 4
  - transcript missing or unreadable fallback is covered in Task 1 and Task 2 step 3
  - testing and manual verification are covered in Task 2 step 6 and Task 3 steps 2 and 3
- Placeholder scan:
  - removed vague “write tests later” phrasing and anchored each behavior to a concrete task or explicit manual verification step
- Type consistency:
  - the plan consistently uses `MeetingTranscriptContent`, `loadMeetingTranscriptContent`, `transcriptPane`, `sidebar`, and `playbackBar`

## Execution Handoff

The implementation plan is ready at `docs/plans/2026-05-06-meeting-detail-redesign.md`. The next step is to execute Task 1 and start with the failing transcript-content tests.
