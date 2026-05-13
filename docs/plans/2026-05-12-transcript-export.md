**Goal:** Add a transcript export action that copies meeting transcript Markdown with title, date, duration, and grouped speaker sections to the user's clipboard, with inline `Copied` feedback in the meeting detail view.

**Architecture:** Keep export formatting in a small pure support file so the Markdown contract is easy to test without UI harnesses. Let `MeetingDetailView` decide whether export is available, trigger the clipboard write on macOS, and manage short-lived inline copy feedback without changing persistence or transcription storage behavior.

**Tech Stack:** Swift, SwiftUI, Foundation, AppKit, Swift Testing, xcodebuild

---

### Task 1: Add the transcript export formatter

**Files:**
- Create: `QuickMeeting/Support/MeetingTranscriptExport.swift`
- Create: `QuickMeetingTests/MeetingTranscriptExportTests.swift`

- [ ] **Step 1: Write the failing formatter tests**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct MeetingTranscriptExportTests {
    @Test
    func exportMarkdownIncludesMeetingHeaderAndGroupedSpeakerSections() {
        let meeting = Meeting(
            title: "Weekly Sync",
            startedAt: Date(timeIntervalSince1970: 1_715_324_800),
            endedAt: Date(timeIntervalSince1970: 1_715_328_700),
            status: .completed,
            audioFilePath: "/tmp/audio.wav",
            duration: 3_900
        )
        let transcript = StoredTranscript(
            speakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Alice"),
                TranscriptSpeaker(id: "speaker-2", displayName: "Bob")
            ],
            segments: [
                TranscriptSegment(text: "Kickoff update.", startTime: 0, endTime: 2, speakerID: "speaker-1"),
                TranscriptSegment(text: "Next agenda point.", startTime: 2, endTime: 4, speakerID: "speaker-1"),
                TranscriptSegment(text: "Looks good to me.", startTime: 4, endTime: 6, speakerID: "speaker-2")
            ]
        )

        let markdown = renderMeetingTranscriptExportMarkdown(
            meeting: meeting,
            transcript: transcript
        )

        #expect(markdown == """
        # Weekly Sync

        Date: **2024-05-10 12:00**

        Duration: **01:05**

        ## Alice
        Kickoff update.

        Next agenda point.

        ## Bob
        Looks good to me.
        """)
    }

    @Test
    func exportMarkdownUsesFallbacksForUntitledMeetingUnknownSpeakerAndMissingDuration() {
        let meeting = Meeting(
            title: "   ",
            startedAt: Date(timeIntervalSince1970: 1_715_328_400),
            status: .completed,
            audioFilePath: "/tmp/audio.wav"
        )
        let transcript = StoredTranscript(
            speakers: [],
            segments: [
                TranscriptSegment(text: "  Hello there.  ", startTime: 0, endTime: 1, speakerID: nil),
                TranscriptSegment(text: "   ", startTime: 1, endTime: 2, speakerID: nil)
            ]
        )

        let markdown = renderMeetingTranscriptExportMarkdown(
            meeting: meeting,
            transcript: transcript
        )

        #expect(markdown == """
        # Untitled Meeting

        Date: **2024-05-10 13:00**

        Duration: **00:00**

        ## Speaker
        Hello there.
        """)
    }
}
```

- [ ] **Step 2: Run the focused formatter tests to verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptExportTests`
Expected: FAIL because `MeetingTranscriptExport.swift`, `MeetingTranscriptExportTests.swift`, and `renderMeetingTranscriptExportMarkdown(...)` do not exist yet.

- [ ] **Step 3: Write the minimal formatter implementation**

```swift
import Foundation

func renderMeetingTranscriptExportMarkdown(
    meeting: Meeting,
    transcript: StoredTranscript
) -> String {
    let speakerNames = Dictionary(uniqueKeysWithValues: transcript.speakers.map { ($0.id, $0.displayName) })
    let title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "Untitled Meeting"
        : meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = .current
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

    let groupedSegments = transcript.segments.reduce(into: [(speakerName: String, lines: [String])]()) { result, segment in
        let line = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            return
        }

        let speakerName = segment.speakerID.flatMap { speakerNames[$0] } ?? "Speaker"
        if result.last?.speakerName == speakerName {
            result[result.count - 1].lines.append(line)
        } else {
            result.append((speakerName: speakerName, lines: [line]))
        }
    }

    let sections = groupedSegments.map { group in
        "## \(group.speakerName)\n" + group.lines.joined(separator: "\n\n")
    }

    let durationText = transcriptExportDurationText(meeting.duration)

    return ([
        "# \(title)",
        "Date: **\(dateFormatter.string(from: meeting.startedAt))**",
        "Duration: **\(durationText)**"
    ] + sections).joined(separator: "\n\n")
}

func transcriptExportDurationText(_ duration: TimeInterval?) -> String {
    guard let duration else {
        return "00:00"
    }

    let totalMinutes = max(Int(duration.rounded(.down)) / 60, 0)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return String(format: "%02d:%02d", hours, minutes)
}
```

- [ ] **Step 4: Run the focused formatter tests to verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptExportTests`
Expected: PASS.

- [ ] **Step 5: Commit the formatter slice**

```bash
git add QuickMeeting/Support/MeetingTranscriptExport.swift QuickMeetingTests/MeetingTranscriptExportTests.swift
git commit -m "test: add transcript export formatter"
```

### Task 2: Add export availability helpers

**Files:**
- Modify: `QuickMeeting/Support/MeetingTranscriptContent.swift`
- Modify: `QuickMeetingTests/MeetingTranscriptContentTests.swift`

- [ ] **Step 1: Write the failing export-availability tests**

```swift
@Test
func transcriptExportAvailabilityRequiresAtLeastOneNonEmptySegment() {
    let available = isTranscriptExportAvailable(
        from: StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: " Hello ", startTime: 0, endTime: 1, speakerID: "speaker-1")]
        )
    )

    #expect(available)
}

@Test
func transcriptExportAvailabilityRejectsMissingOrWhitespaceOnlyTranscript() {
    #expect(!isTranscriptExportAvailable(from: nil))
    #expect(
        !isTranscriptExportAvailable(
            from: StoredTranscript(
                speakers: [],
                segments: [TranscriptSegment(text: "   ", startTime: 0, endTime: 1, speakerID: nil)]
            )
        )
    )
}
```

- [ ] **Step 2: Run the focused transcript-content tests to verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptContentTests`
Expected: FAIL because `isTranscriptExportAvailable(from:)` does not exist yet.

- [ ] **Step 3: Write the minimal export-availability helper**

```swift
func isTranscriptExportAvailable(from transcript: StoredTranscript?) -> Bool {
    guard let transcript else {
        return false
    }

    return transcript.segments.contains { segment in
        !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

- [ ] **Step 4: Run the focused transcript-content tests to verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptContentTests`
Expected: PASS.

- [ ] **Step 5: Commit the availability helper slice**

```bash
git add QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "test: add transcript export availability helper"
```

### Task 3: Wire export and copy feedback into the meeting detail view

**Files:**
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Test: `QuickMeetingTests/MeetingTranscriptExportTests.swift`
- Test: `QuickMeetingTests/MeetingTranscriptContentTests.swift`

- [ ] **Step 1: Write the failing meeting-detail export state tests**

```swift
@Test
func exportDurationRoundsDownToWholeMinutes() {
    #expect(transcriptExportDurationText(59) == "00:00")
    #expect(transcriptExportDurationText(60) == "00:01")
    #expect(transcriptExportDurationText(3_661) == "01:01")
}
```

- [ ] **Step 2: Run the focused export tests to verify they fail for the new edge case**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptExportTests`
Expected: FAIL until `transcriptExportDurationText(_:)` handles the documented minute-based formatting.

- [ ] **Step 3: Update `MeetingDetailView` with export action and inline copy feedback**

```swift
#if canImport(AppKit)
import AppKit
#endif
import SwiftUI

struct MeetingDetailView: View {
    // existing stored properties...
    @State private var exportFeedbackText: String?
    @State private var exportFeedbackTask: Task<Void, Never>?

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.headline)

            Button("Transcribe", action: handleTranscribeAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canTranscribe)

            HStack(spacing: 10) {
                Button("Export Transcript", action: copyTranscriptExport)
                    .disabled(!isTranscriptExportAvailable(from: meeting.storedTranscript))

                if let exportFeedbackText {
                    Text(exportFeedbackText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Delete Meeting", role: .destructive) {
                isShowingDeleteConfirmation = true
            }
            .disabled(!canDelete)
        }
    }

    private func copyTranscriptExport() {
        guard let transcript = meeting.storedTranscript,
              isTranscriptExportAvailable(from: meeting.storedTranscript) else {
            return
        }

        let markdown = renderMeetingTranscriptExportMarkdown(
            meeting: meeting,
            transcript: transcript
        )

        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #endif

        exportFeedbackTask?.cancel()
        exportFeedbackText = "Copied"
        exportFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                exportFeedbackText = nil
                exportFeedbackTask = nil
            }
        }
    }
}
```

- [ ] **Step 4: Run the focused export-related tests to verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptExportTests -only-testing:QuickMeetingTests/MeetingTranscriptContentTests`
Expected: PASS.

- [ ] **Step 5: Commit the UI export slice**

```bash
git add QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/Support/MeetingTranscriptExport.swift QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeetingTests/MeetingTranscriptExportTests.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "feat: add transcript export action"
```

### Task 4: Run final verification for the feature

**Files:**
- Test: `QuickMeetingTests/MeetingTranscriptExportTests.swift`
- Test: `QuickMeetingTests/MeetingTranscriptContentTests.swift`
- Test: `QuickMeetingTests/TranscriptMarkdownRenderingTests.swift`

- [ ] **Step 1: Run the full focused verification suite**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingTranscriptExportTests -only-testing:QuickMeetingTests/MeetingTranscriptContentTests -only-testing:QuickMeetingTests/TranscriptMarkdownRenderingTests`
Expected: PASS with all selected tests green.

- [ ] **Step 2: Review the final diff for scope**

Run: `git diff -- QuickMeeting/Support/MeetingTranscriptExport.swift QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeetingTests/MeetingTranscriptExportTests.swift QuickMeetingTests/MeetingTranscriptContentTests.swift`
Expected: Diff only shows the export formatter, availability helper, meeting detail export UI, and tests for those behaviors.

- [ ] **Step 3: Commit the verified feature if the last slice was amended locally during verification**

```bash
git add QuickMeeting/Support/MeetingTranscriptExport.swift QuickMeeting/Support/MeetingTranscriptContent.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeetingTests/MeetingTranscriptExportTests.swift QuickMeetingTests/MeetingTranscriptContentTests.swift
git commit -m "chore: verify transcript export coverage"
```

Skip this step if no verification changes were needed after Task 3.
