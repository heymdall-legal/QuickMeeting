**Goal:** Add in-app playback controls for a saved meeting recording in the meeting detail screen.

**Architecture:** Introduce a small observable playback controller that wraps native audio playback and owns file-loading, state transitions, and error reporting. Keep the player scoped to `MeetingDetailView` so playback stays local to the selected meeting while remaining testable through a narrow abstraction.

**Tech Stack:** SwiftUI, AVFAudio, Swift Testing, Foundation

---

## File Map

- Create: `QuickMeeting/Services/Playback/MeetingAudioPlayback.swift`
  Responsibility: define playback state, a native-player abstraction, and an observable controller that loads a meeting file, toggles play/pause, and reports user-facing errors.
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
  Responsibility: render in-app playback controls and bind them to the playback controller for the selected meeting.
- Modify: `QuickMeeting/ContentView.swift`
  Responsibility: pass the selected meeting into the detail view in a way that lets the view refresh playback state when selection changes. This may remain unchanged if `MeetingDetailView` handles selection changes through its `meeting` input cleanly.
- Create: `QuickMeetingTests/MeetingAudioPlaybackTests.swift`
  Responsibility: verify controller state transitions, missing-file handling, and selection reload behavior with test doubles.

### Task 1: Playback Controller

**Files:**
- Create: `QuickMeetingTests/MeetingAudioPlaybackTests.swift`
- Create: `QuickMeeting/Services/Playback/MeetingAudioPlayback.swift`
- Test: `QuickMeetingTests/MeetingAudioPlaybackTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct MeetingAudioPlaybackTests {
    final class NativeAudioPlayerSpy: NativeAudioPlaying {
        private(set) var loadedURL: URL?
        private(set) var playCallCount = 0
        private(set) var pauseCallCount = 0
        private(set) var stopCallCount = 0
        private(set) var prepareToPlayCallCount = 0

        func markLoaded(url: URL) {
            loadedURL = url
        }

        func play() {
            playCallCount += 1
        }

        func pause() {
            pauseCallCount += 1
        }

        func stop() {
            stopCallCount += 1
        }

        func prepareToPlay() {
            prepareToPlayCallCount += 1
        }
    }

    @Test
    func loadReadyFileTransitionsToReadyState() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        let nativePlayer = NativeAudioPlayerSpy()
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                nativePlayer.markLoaded(url: url)
                return nativePlayer
            }
        )

        try playback.loadAudioFile(at: audioURL)

        #expect(playback.state == .ready)
        #expect(nativePlayer.loadedURL == audioURL)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-playback-red CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests/loadReadyFileTransitionsToReadyState
```

Expected: FAIL because `MeetingAudioPlayback`, `NativeAudioPlayerSpy`, or `loadAudioFile(at:)` do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
import AVFAudio
import Foundation

enum MeetingAudioPlaybackState: Equatable {
    case idle
    case ready
    case playing
    case paused
    case failed(message: String)
}

protocol NativeAudioPlaying: AnyObject {
    func play()
    func pause()
    func stop()
}

@MainActor
final class MeetingAudioPlayback: ObservableObject {
    @Published private(set) var state: MeetingAudioPlaybackState = .idle

    private let fileManager: FileManager
    private let nativePlayerFactory: (URL) throws -> NativeAudioPlaying
    private var nativePlayer: NativeAudioPlaying?

    init(
        fileManager: FileManager = .default,
        nativePlayerFactory: @escaping (URL) throws -> NativeAudioPlaying = { url in
            try AVAudioPlayerAdapter(contentsOf: url)
        }
    ) {
        self.fileManager = fileManager
        self.nativePlayerFactory = nativePlayerFactory
    }

    func loadAudioFile(at fileURL: URL) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            nativePlayer = nil
            state = .failed(message: "Recording file is missing.")
            return
        }

        nativePlayer = try nativePlayerFactory(fileURL)
        state = .ready
    }
}

final class AVAudioPlayerAdapter: NSObject, NativeAudioPlaying {
    private let player: AVAudioPlayer

    init(contentsOf url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.prepareToPlay()
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.stop()
        player.currentTime = 0
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-playback-green CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests/loadReadyFileTransitionsToReadyState
```

Expected: PASS for `loadReadyFileTransitionsToReadyState`.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Playback/MeetingAudioPlayback.swift QuickMeetingTests/MeetingAudioPlaybackTests.swift
git commit -m "feat: add meeting audio playback controller"
```

### Task 2: Playback State Transitions and Error Handling

**Files:**
- Modify: `QuickMeetingTests/MeetingAudioPlaybackTests.swift`
- Modify: `QuickMeeting/Services/Playback/MeetingAudioPlayback.swift`
- Test: `QuickMeetingTests/MeetingAudioPlaybackTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
    @Test
    func togglePlaybackMovesBetweenPlayingAndPausedStates() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        let nativePlayer = NativeAudioPlayerSpy()
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                nativePlayer.markLoaded(url: url)
                return nativePlayer
            }
        )
        try playback.loadAudioFile(at: audioURL)

        playback.togglePlayback()
        #expect(playback.state == .playing)
        #expect(nativePlayer.playCallCount == 1)

        playback.togglePlayback()
        #expect(playback.state == .paused)
        #expect(nativePlayer.pauseCallCount == 1)
    }

    @Test
    func loadMissingFileProducesFriendlyFailureState() throws {
        let fileManager = FileManager.default
        let missingURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("missing.wav")
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                let player = NativeAudioPlayerSpy()
                player.markLoaded(url: url)
                return player
            }
        )

        try playback.loadAudioFile(at: missingURL)

        #expect(playback.state == .failed(message: "Recording file is missing."))
    }

    @Test
    func loadNewFileStopsCurrentPlaybackAndPreparesNewSelection() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let firstURL = rootURL.appendingPathComponent("first.wav")
        let secondURL = rootURL.appendingPathComponent("second.wav")
        fileManager.createFile(atPath: firstURL.path, contents: Data("first".utf8))
        fileManager.createFile(atPath: secondURL.path, contents: Data("second".utf8))

        let firstPlayer = NativeAudioPlayerSpy()
        let secondPlayer = NativeAudioPlayerSpy()
        var queuedPlayers = [firstPlayer, secondPlayer]
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                let player = queuedPlayers.removeFirst()
                player.markLoaded(url: url)
                return player
            }
        )

        try playback.loadAudioFile(at: firstURL)
        playback.togglePlayback()

        try playback.loadAudioFile(at: secondURL)

        #expect(firstPlayer.stopCallCount == 1)
        #expect(secondPlayer.loadedURL == secondURL)
        #expect(playback.state == .ready)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-playback-red CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests
```

Expected: FAIL because `togglePlayback()` and reload-stop behavior are not implemented yet.

- [ ] **Step 3: Write minimal implementation**

```swift
protocol NativeAudioPlaying: AnyObject {
    func play()
    func pause()
    func stop()
    func prepareToPlay()
}

@MainActor
final class MeetingAudioPlayback: ObservableObject {
    @Published private(set) var state: MeetingAudioPlaybackState = .idle

    private let fileManager: FileManager
    private let nativePlayerFactory: (URL) throws -> NativeAudioPlaying
    private var nativePlayer: NativeAudioPlaying?

    func loadAudioFile(at fileURL: URL) throws {
        nativePlayer?.stop()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            nativePlayer = nil
            state = .failed(message: "Recording file is missing.")
            return
        }

        let player = try nativePlayerFactory(fileURL)
        player.prepareToPlay()
        nativePlayer = player
        state = .ready
    }

    func togglePlayback() {
        guard let nativePlayer else {
            return
        }

        switch state {
        case .ready, .paused:
            nativePlayer.play()
            state = .playing
        case .playing:
            nativePlayer.pause()
            state = .paused
        case .idle, .failed:
            return
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-playback-green CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests
```

Expected: PASS for all `MeetingAudioPlaybackTests`.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Playback/MeetingAudioPlayback.swift QuickMeetingTests/MeetingAudioPlaybackTests.swift
git commit -m "test: cover meeting audio playback state changes"
```

### Task 3: Meeting Detail Playback UI

**Files:**
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Test: `QuickMeetingTests/MeetingAudioPlaybackTests.swift`

- [ ] **Step 1: Write the failing UI-oriented test**

```swift
    @Test
    func loadErrorLeavesPlaybackUnavailableForTheView() throws {
        let fileManager = FileManager.default
        let missingURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("missing.wav")
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                let player = NativeAudioPlayerSpy()
                player.markLoaded(url: url)
                return player
            }
        )

        try playback.loadAudioFile(at: missingURL)

        #expect(playback.isPlaybackAvailable == false)
        #expect(playback.statusText == "Recording file is missing.")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-playback-red CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests/loadErrorLeavesPlaybackUnavailableForTheView
```

Expected: FAIL because `isPlaybackAvailable` and `statusText` do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
@MainActor
final class MeetingAudioPlayback: ObservableObject {
    var isPlaybackAvailable: Bool {
        switch state {
        case .ready, .playing, .paused:
            return true
        case .idle, .failed:
            return false
        }
    }

    var statusText: String {
        switch state {
        case .idle:
            return "Select a recording to prepare playback."
        case .ready:
            return "Ready"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .failed(let message):
            return message
        }
    }
}

struct MeetingDetailView: View {
    let meeting: Meeting
    @StateObject private var playback = MeetingAudioPlayback()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // existing metadata

                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Playback")
                        .font(.headline)

                    Button(playbackButtonTitle) {
                        playback.togglePlayback()
                    }
                    .disabled(!playback.isPlaybackAvailable)

                    Text(playback.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Audio File")
                        .font(.headline)
                    Text(meeting.audioFilePath)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
        }
        .task(id: meeting.id) {
            try? playback.loadAudioFile(at: URL(fileURLWithPath: meeting.audioFilePath))
        }
    }

    private var playbackButtonTitle: String {
        switch playback.state {
        case .playing:
            return "Pause"
        default:
            return "Play"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-playback-green CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests
```

Expected: PASS for the playback tests, with the view able to consume the new playback properties.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/Services/Playback/MeetingAudioPlayback.swift QuickMeetingTests/MeetingAudioPlaybackTests.swift
git commit -m "feat: add in-app playback to meeting detail view"
```

### Task 4: Full Verification

**Files:**
- Modify: `QuickMeeting/Services/Playback/MeetingAudioPlayback.swift`
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeetingTests/MeetingAudioPlaybackTests.swift`

- [ ] **Step 1: Run focused playback tests**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-playback-verify CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests
```

Expected: PASS for all playback tests.

- [ ] **Step 2: Run the existing app test suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-playback-verify CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
```

Expected: PASS for `QuickMeetingTests` with no regressions in recording or persistence behavior.

- [ ] **Step 3: If verification fails, patch only the failing playback integration**

If either verification run fails, limit the fix to one of these files:

- `QuickMeeting/Services/Playback/MeetingAudioPlayback.swift`
- `QuickMeeting/Views/MeetingDetailView.swift`
- `QuickMeetingTests/MeetingAudioPlaybackTests.swift`

Use the smallest targeted change that matches the failure. Typical examples are:

- stopping the previous player before loading a new meeting
- correcting the reported `MeetingAudioPlaybackState`
- refreshing the detail view’s `.task(id: meeting.id)` loading path

If both verification runs already pass, make no code change in this step.

- [ ] **Step 4: Re-run the affected tests**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-audio-playback-verify CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingAudioPlaybackTests -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/MeetingFileStoreTests
```

Expected: PASS for the previously failing areas and the new playback behavior.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Playback/MeetingAudioPlayback.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeetingTests/MeetingAudioPlaybackTests.swift
git commit -m "chore: verify meeting audio playback"
```
