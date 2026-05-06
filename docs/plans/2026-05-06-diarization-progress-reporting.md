# Diarization Progress Reporting

## Context

After transcription finishes, diarization runs via a single async black-box call (`SpeakerKit.diarize(audioArray:)`) with no real progress callback. The UI currently shows nothing new during this phase — it stays at "Transcribing... 100%". The goal is to switch to a "Diarization" label with a 0→100% progress bar once transcription completes. Since SpeakerKit provides no progress, we simulate it using a background Task that increments exponentially toward 95%, then snaps to 100% when `diarize` returns.

---

## Files to Modify

1. `QuickMeeting/Services/Transcription/TranscriptionProgressCenter.swift`
2. `QuickMeeting/Support/MeetingTranscriptionProgressDisplay.swift`
3. `QuickMeeting/Services/Transcription/TranscriptionService.swift`
4. `QuickMeeting/ViewModels/AppViewModel.swift`
5. `QuickMeeting/ContentView.swift`
6. `QuickMeeting/Views/MeetingDetailView.swift`
7. `QuickMeetingTests/MeetingTranscriptionProgressDisplayTests.swift`
8. `QuickMeetingTests/TranscriptionProgressCenterTests.swift` (new tests only)

---

## Step-by-Step Changes

### 1. `TranscriptionProgressCenter.swift`

Add a separate diarization dict alongside the existing transcription one:

```swift
@Published private var diarizationProgressByMeetingID: [UUID: Double] = [:]

func startDiarizationTracking(meetingID: UUID) {
    diarizationProgressByMeetingID[meetingID] = 0
}

func updateDiarizationProgress(_ progress: Double, for meetingID: UUID) {
    guard let current = diarizationProgressByMeetingID[meetingID] else { return }
    let clamped = min(max(progress, 0), 1)
    guard clamped >= current else { return }
    diarizationProgressByMeetingID[meetingID] = clamped
}

func diarizationProgress(for meetingID: UUID) -> Double? {
    diarizationProgressByMeetingID[meetingID]
}
```

Update `finishTracking` to also clear the diarization dict:

```swift
func finishTracking(meetingID: UUID) {
    progressByMeetingID.removeValue(forKey: meetingID)
    diarizationProgressByMeetingID.removeValue(forKey: meetingID)   // ADD
}
```

### 2. `MeetingTranscriptionProgressDisplay.swift`

Add `.diarizing` case to the enum:

```swift
enum TranscriptPaneState: Equatable {
    case empty
    case transcribing(progress: Double)
    case diarizing(progress: Double)       // NEW
    case transcriptFile(String)
}
```

Update `transcriptPaneState` signature and body (prefer diarizing when its entry exists):

```swift
func transcriptPaneState(
    meetingStatus: MeetingStatus,
    transcriptFilePath: String?,
    progress: Double?,
    diarizationProgress: Double?           // NEW param
) -> TranscriptPaneState {
    if meetingStatus == .transcribing {
        if let diarizationProgress {
            return .diarizing(progress: min(max(diarizationProgress, 0), 1))
        }
        if let progress {
            return .transcribing(progress: min(max(progress, 0), 1))
        }
    }
    if let transcriptFilePath {
        return .transcriptFile(transcriptFilePath)
    }
    return .empty
}
```

Add a helper (mirrors `transcriptionProgressText`):

```swift
func diarizationProgressText(_ progress: Double) -> String {
    "\(Int(min(max(progress, 0), 1) * 100))% complete"
}
```

### 3. `TranscriptionService.swift`

Add stored property for the simulation task (alongside `activeMeetingID`):

```swift
private var diarizationSimulationTask: Task<Void, Never>?
```

Update the `defer` block to cancel the simulation task before `finishTracking`:

```swift
defer {
    diarizationSimulationTask?.cancel()
    diarizationSimulationTask = nil
    progressCenter.finishTracking(meetingID: meetingID)
    activeMeetingID = nil
}
```

After `backend.transcribe(...)` returns and before `diarizer.diarize(...)`, insert:

```swift
progressCenter.startDiarizationTracking(meetingID: meetingID)

diarizationSimulationTask = Task { [progressCenter] in
    var elapsed: Double = 0
    let totalDuration: Double = 30
    let tickInterval: Double = 0.5
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(tickInterval))
        guard !Task.isCancelled else { break }
        elapsed += tickInterval
        // Exponential approach: 1 - e^(-3t/T), capped at 0.95
        let simulated = min(0.95, 1.0 - exp(-3.0 * elapsed / totalDuration))
        await MainActor.run {
            progressCenter.updateDiarizationProgress(simulated, for: meetingID)
        }
    }
}

let storedTranscript = try await diarizer.diarize(
    TranscriptDiarizationRequest(audioFileURL: audioFileURL, result: result)
)

diarizationSimulationTask?.cancel()
diarizationSimulationTask = nil
progressCenter.updateDiarizationProgress(1.0, for: meetingID)
```

On the error path the `defer` handles cleanup automatically.

### 4. `AppViewModel.swift`

Add a pass-through method next to the existing `transcriptionProgress(for:)`:

```swift
func diarizationProgress(for meetingID: UUID) -> Double? {
    transcriptionProgressCenter.diarizationProgress(for: meetingID)
}
```

### 5. `ContentView.swift`

Pass the new parameter to `MeetingDetailView`:

```swift
MeetingDetailView(
    meeting: selectedMeeting,
    transcriptionProgress: appViewModel.transcriptionProgress(for: selectedMeeting.id),
    diarizationProgress: appViewModel.diarizationProgress(for: selectedMeeting.id),  // NEW
    ...
)
```

### 6. `MeetingDetailView.swift`

Add the new stored property next to `transcriptionProgress`:

```swift
let diarizationProgress: Double?
```

Update `currentTranscriptPaneState` to pass it:

```swift
private var currentTranscriptPaneState: TranscriptPaneState {
    transcriptPaneState(
        meetingStatus: (try? meeting.status) ?? .recorded,
        transcriptFilePath: meeting.transcriptFilePath,
        progress: transcriptionProgress,
        diarizationProgress: diarizationProgress   // NEW
    )
}
```

Add `.diarizing` branch in `transcriptPane`'s switch:

```swift
case .diarizing(let progress):
    diarizationProgressState(progress: progress)
```

Add the new view method (mirrors `transcriptionProgressState`):

```swift
private func diarizationProgressState(progress: Double) -> some View {
    VStack(spacing: 12) {
        Text("Diarization")
            .font(.title3)
            .fontWeight(.semibold)
        ProgressView(value: progress)
            .frame(maxWidth: 280)
        Text(diarizationProgressText(progress))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

### 7. Tests — `MeetingTranscriptionProgressDisplayTests.swift`

Fix the two existing call sites by adding `diarizationProgress: nil`.

Add two new tests:

```swift
@Test
func diarizingMeetingUsesDiarizingPane() {
    let state = transcriptPaneState(
        meetingStatus: .transcribing,
        transcriptFilePath: nil,
        progress: nil,
        diarizationProgress: 0.6
    )
    #expect(state == .diarizing(progress: 0.6))
}

@Test
func diarizationTakesPrecedenceOverTranscriptionProgress() {
    let state = transcriptPaneState(
        meetingStatus: .transcribing,
        transcriptFilePath: nil,
        progress: 1.0,
        diarizationProgress: 0.3
    )
    #expect(state == .diarizing(progress: 0.3))
}
```

### 8. Tests — `TranscriptionProgressCenterTests.swift`

Add three tests:
- `startDiarizationTrackingRegistersZeroProgress` — verifies `diarizationProgress(for:) == 0`
- `updateDiarizationProgressClampsAndIgnoresRegressions` — mirrors the transcription version
- `finishTrackingClearsDiarizationProgress` — calls both start methods, then `finishTracking`, expects both `progress(for:)` and `diarizationProgress(for:)` to be nil

---

## Verification

1. Build and run; trigger transcription on a recorded meeting
2. During transcription: progress bar shows "Transcribing..." with 0→100%
3. After transcription completes: label switches to "Diarization" and bar animates from 0 toward 100%
4. When diarization finishes: transcript appears
5. Run test suite — all existing + new tests pass
