**Goal:** Improve the meeting detail audio player so it shows playback progress, returns to a non-playing state at the end, and supports seeking.

**Architecture:** Extend `MeetingAudioPlayback` into a time-aware observable playback model that owns progress updates, native-player completion handling, and seek behavior. Keep `MeetingDetailView` as a thin SwiftUI consumer that renders a scrubber and time labels from the model.

**Tech Stack:** Swift, SwiftUI, AVFAudio, Testing, xcodebuild

---

### Task 1: Add failing playback-model tests for progress, completion, and seeking

**Files:**
- Modify: `/Users/heymdall/Developer/QuickMeeting/QuickMeetingTests/MeetingAudioPlaybackTests.swift`
- Test: `/Users/heymdall/Developer/QuickMeeting/QuickMeetingTests/MeetingAudioPlaybackTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@Test
func loadReadyFilePublishesDuration() throws {
    // Load a file with a spy player that reports a duration.
    // Expect playback.duration to equal the spy duration and currentTime to start at 0.
}

@Test
func playbackCompletionResetsStateAndTime() throws {
    // Start playback, simulate native completion, and expect state == .ready and currentTime == 0.
}

@Test
func seekUpdatesNativePlayerTimeAndPublishedProgress() throws {
    // Load a file, seek to a new time, and expect the spy currentTime plus the observable currentTime to match.
}
```

- [ ] **Step 2: Run the focused test target to verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-player-red CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests`

Expected: FAIL because `MeetingAudioPlayback` does not yet expose duration, current time, completion handling, or seeking.

- [ ] **Step 3: Write the minimal implementation**

```swift
protocol NativeAudioPlaying: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var onFinishPlayback: (() -> Void)? { get set }
    func play()
    func pause()
    func stop()
    func prepareToPlay()
}
```

```swift
@Published private(set) var currentTime: TimeInterval = 0
@Published private(set) var duration: TimeInterval = 0

func seek(to time: TimeInterval) {
    guard let nativePlayer else { return }
    let clampedTime = min(max(time, 0), duration)
    nativePlayer.currentTime = clampedTime
    currentTime = clampedTime
}
```

- [ ] **Step 4: Run the focused test target to verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-player-green CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests`

Expected: PASS for the playback tests.

- [ ] **Step 5: Commit**

```bash
git add /Users/heymdall/Developer/QuickMeeting/QuickMeeting/Services/Playback/MeetingAudioPlayback.swift /Users/heymdall/Developer/QuickMeeting/QuickMeetingTests/MeetingAudioPlaybackTests.swift
git commit -m "feat: add meeting audio playback progress state"
```

### Task 2: Render the playback scrubber and time labels in the detail view

**Files:**
- Modify: `/Users/heymdall/Developer/QuickMeeting/QuickMeeting/Views/MeetingDetailView.swift`
- Test: `/Users/heymdall/Developer/QuickMeeting/QuickMeetingTests/MeetingAudioPlaybackTests.swift`

- [ ] **Step 1: Write the failing test for view-facing playback data if needed**

```swift
@Test
func loadErrorLeavesPlaybackUnavailableForTheView() throws {
    // Keep the existing view-facing availability assertion and extend it
    // to verify time-aware state stays safe for the UI.
}
```

- [ ] **Step 2: Run the focused test target to verify it fails if the new UI contract is missing**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-player-view-red CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests`

Expected: FAIL only if the added UI-facing playback contract is not yet satisfied.

- [ ] **Step 3: Write the minimal view implementation**

```swift
Slider(
    value: Binding(
        get: { playback.currentTime },
        set: { playback.seek(to: $0) }
    ),
    in: 0...max(playback.duration, 0.1)
)

HStack {
    Text(playback.elapsedTimeText)
    Spacer()
    Text(playback.durationText)
}
```

- [ ] **Step 4: Run the focused test target to verify it still passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-player-view-green CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests`

Expected: PASS while the detail view consumes the new playback data.

- [ ] **Step 5: Commit**

```bash
git add /Users/heymdall/Developer/QuickMeeting/QuickMeeting/Views/MeetingDetailView.swift
git commit -m "feat: add meeting audio playback scrubber"
```

### Task 3: Verify the playback improvements against the focused suite

**Files:**
- Modify: `/Users/heymdall/Developer/QuickMeeting/QuickMeeting/Services/Playback/MeetingAudioPlayback.swift`
- Modify: `/Users/heymdall/Developer/QuickMeeting/QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `/Users/heymdall/Developer/QuickMeeting/QuickMeetingTests/MeetingAudioPlaybackTests.swift`

- [ ] **Step 1: Run the focused playback suite**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-player-verify CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests`

Expected: PASS for progress, completion reset, seeking, and existing playback behavior.

- [ ] **Step 2: Run the broader related suite**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-player-verify CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/MeetingFileStoreTests`

Expected: PASS with no regressions in meeting detail playback integration or meeting persistence behavior.

- [ ] **Step 3: Commit the verified implementation**

```bash
git add /Users/heymdall/Developer/QuickMeeting/QuickMeeting/Services/Playback/MeetingAudioPlayback.swift /Users/heymdall/Developer/QuickMeeting/QuickMeeting/Views/MeetingDetailView.swift /Users/heymdall/Developer/QuickMeeting/QuickMeetingTests/MeetingAudioPlaybackTests.swift
git commit -m "feat: improve meeting detail audio player"
```

## Self-Review

- Spec coverage: the plan covers visible progress, completion reset, seeking, and focused verification.
- Placeholder scan: all tasks include concrete files, commands, and code targets.
- Type consistency: the plan uses `currentTime`, `duration`, `seek(to:)`, and a finish callback consistently across model, tests, and view.
