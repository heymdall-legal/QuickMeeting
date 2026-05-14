**Goal:** Make auto-recording require active microphone usage plus selected-app evidence, using a CoreAudio-backed microphone activity source and a 30-second recent-focus window.

**Architecture:** Keep the existing `MeetingAppMonitor` and `AutoRecordingCoordinator` flow intact, but replace the dead `isUsingMedia` heuristic with an explicit `isMicrophoneActive` signal. Introduce a small `MicrophoneActivitySource` abstraction with a native CoreAudio implementation, then update `NativeMeetingAppActivitySource` to combine microphone state, visible-window state, and recent-focus timestamps into one sample that `MeetingPresenceDetector` can evaluate deterministically.

**Tech Stack:** Swift, AppKit, CoreAudio, Foundation, Testing, xcodebuild

---

## File Structure

**Create:**
- `QuickMeeting/Services/AutoRecording/MicrophoneActivitySource.swift`
- `QuickMeeting/Services/AutoRecording/NativeMicrophoneActivitySource.swift`
- `QuickMeetingTests/NativeMeetingAppActivitySourceTests.swift`
- `QuickMeetingTests/NativeMicrophoneActivitySourceTests.swift`

**Modify:**
- `QuickMeeting/Models/MeetingAppPresence.swift`
- `QuickMeeting/Services/AutoRecording/MeetingPresenceDetector.swift`
- `QuickMeeting/Services/AutoRecording/NativeMeetingAppActivitySource.swift`
- `QuickMeetingTests/MeetingPresenceDetectorTests.swift`
- `QuickMeetingTests/AppViewModelTests.swift`
- `docs/quickmeeting-architecture-design.md`

**Why these files:**
- `MicrophoneActivitySource.swift` and `NativeMicrophoneActivitySource.swift` isolate the BeezyLight-style CoreAudio detection behind a tiny interface so the rest of the app does not depend on HAL details.
- `MeetingAppPresence.swift` and `MeetingPresenceDetector.swift` are where the product rule changes become explicit and testable.
- `NativeMeetingAppActivitySource.swift` is the right integration point for combining microphone state with app visibility and recent focus because it already owns selected-app sampling.
- `NativeMeetingAppActivitySourceTests.swift` and `NativeMicrophoneActivitySourceTests.swift` cover the new time-based and device-based behavior without needing real macOS device state in tests.
- `AppViewModelTests.swift` and `docs/quickmeeting-architecture-design.md` keep the integration contract and docs aligned with the implementation.

### Task 1: Make microphone activity an explicit detector input

**Files:**
- Modify: `QuickMeeting/Models/MeetingAppPresence.swift`
- Modify: `QuickMeeting/Services/AutoRecording/MeetingPresenceDetector.swift`
- Modify: `QuickMeetingTests/MeetingPresenceDetectorTests.swift`

- [ ] **Step 1: Rewrite the detector tests to express the new product rule**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct MeetingPresenceDetectorTests {
    @Test
    func inactiveWhenMicrophoneIsOffEvenIfAppSignalsMatch() {
        var detector = MeetingPresenceDetector(requiredStableSampleCount: 3)
        let sample = MeetingAppActivitySample(
            bundleIdentifier: "kontur.talk",
            isRunning: true,
            isFrontmost: true,
            hadRecentFocus: true,
            hasVisibleWindow: true,
            isMicrophoneActive: false
        )

        #expect(detector.evaluate(sample) == .inactive)
        #expect(detector.evaluate(sample) == .inactive)
    }

    @Test
    func promotesCandidateToActiveWhenMicrophoneAndAppEvidenceStayStable() {
        var detector = MeetingPresenceDetector(requiredStableSampleCount: 3)
        let sample = MeetingAppActivitySample(
            bundleIdentifier: "kontur.talk",
            isRunning: true,
            isFrontmost: false,
            hadRecentFocus: true,
            hasVisibleWindow: false,
            isMicrophoneActive: true
        )

        #expect(detector.evaluate(sample) == .candidateActive)
        #expect(detector.evaluate(sample) == .candidateActive)
        #expect(detector.evaluate(sample) == .activeMeeting)
    }

    @Test
    func resetsToInactiveWhenMicrophoneDrops() {
        var detector = MeetingPresenceDetector(requiredStableSampleCount: 2)
        let activeSample = MeetingAppActivitySample(
            bundleIdentifier: "kontur.talk",
            isRunning: true,
            isFrontmost: true,
            hadRecentFocus: true,
            hasVisibleWindow: true,
            isMicrophoneActive: true
        )
        let inactiveSample = MeetingAppActivitySample(
            bundleIdentifier: "kontur.talk",
            isRunning: true,
            isFrontmost: true,
            hadRecentFocus: true,
            hasVisibleWindow: true,
            isMicrophoneActive: false
        )

        #expect(detector.evaluate(activeSample) == .candidateActive)
        #expect(detector.evaluate(activeSample) == .activeMeeting)
        #expect(detector.evaluate(inactiveSample) == .inactive)
        #expect(detector.evaluate(activeSample) == .candidateActive)
    }
}
```

- [ ] **Step 2: Run the targeted detector tests and verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingPresenceDetectorTests`

Expected: FAIL because `MeetingAppActivitySample` still uses `isUsingMedia` and the detector does not require microphone activity.

- [ ] **Step 3: Replace `isUsingMedia` with `isMicrophoneActive` in the sample model**

```swift
import Foundation

struct MeetingAppActivitySample: Equatable, Sendable {
    let bundleIdentifier: String
    let isRunning: Bool
    let isFrontmost: Bool
    let hadRecentFocus: Bool
    let hasVisibleWindow: Bool
    let isMicrophoneActive: Bool
}

enum MeetingAppPresence: Equatable, Sendable {
    case inactive
    case candidateActive
    case activeMeeting
    case ending
}
```

- [ ] **Step 4: Update the detector to gate on microphone activity**

```swift
import Foundation

struct MeetingPresenceDetector {
    private let requiredStableSampleCount: Int
    private var stableMatchCount = 0

    init(requiredStableSampleCount: Int = 3) {
        self.requiredStableSampleCount = requiredStableSampleCount
    }

    mutating func evaluate(_ sample: MeetingAppActivitySample) -> MeetingAppPresence {
        let qualifies = sample.isMicrophoneActive
            && sample.isRunning
            && (sample.hasVisibleWindow || sample.hadRecentFocus)

        guard qualifies else {
            stableMatchCount = 0
            return .inactive
        }

        stableMatchCount += 1
        return stableMatchCount >= requiredStableSampleCount ? .activeMeeting : .candidateActive
    }
}
```

- [ ] **Step 5: Re-run the detector tests and verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingPresenceDetectorTests`

Expected: PASS for all microphone-gating detector tests.

- [ ] **Step 6: Commit the detector rule change**

```bash
git add QuickMeeting/Models/MeetingAppPresence.swift QuickMeeting/Services/AutoRecording/MeetingPresenceDetector.swift QuickMeetingTests/MeetingPresenceDetectorTests.swift
git commit -m "feat: require microphone activity for meeting detection"
```

### Task 2: Add a CoreAudio-backed microphone activity source

**Files:**
- Create: `QuickMeeting/Services/AutoRecording/MicrophoneActivitySource.swift`
- Create: `QuickMeeting/Services/AutoRecording/NativeMicrophoneActivitySource.swift`
- Create: `QuickMeetingTests/NativeMicrophoneActivitySourceTests.swift`

- [ ] **Step 1: Write the failing microphone-source tests around cached device state**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct NativeMicrophoneActivitySourceTests {
    @Test
    func returnsTrueWhenAnyInputDeviceReportsRunning() {
        let source = NativeMicrophoneActivitySource(
            deviceInventory: StubAudioInputDeviceInventory(
                devices: [
                    StubAudioInputDevice(id: "built-in", isRunningSomewhere: false),
                    StubAudioInputDevice(id: "usb-mic", isRunningSomewhere: true)
                ]
            )
        )

        #expect(source.isMicrophoneActive() == true)
    }

    @Test
    func returnsFalseWhenEnumerationFails() {
        let source = NativeMicrophoneActivitySource(
            deviceInventory: FailingAudioInputDeviceInventory()
        )

        #expect(source.isMicrophoneActive() == false)
    }
}
```

- [ ] **Step 2: Run the targeted microphone-source tests and verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeMicrophoneActivitySourceTests`

Expected: FAIL because the microphone source types do not exist yet.

- [ ] **Step 3: Add the microphone activity protocol**

```swift
import Foundation

protocol MicrophoneActivitySource: Sendable {
    func isMicrophoneActive() -> Bool
}
```

- [ ] **Step 4: Add a small native source with injectable CoreAudio inventory**

```swift
import CoreAudio
import Foundation

protocol AudioInputDeviceInventory: Sendable {
    func inputDevices() throws -> [AudioInputDevice]
}

protocol AudioInputDevice: Sendable {
    var id: String { get }
    func isRunningSomewhere() throws -> Bool
    func installRunningListener(_ onChange: @escaping @Sendable () -> Void) throws
}

final class NativeMicrophoneActivitySource: MicrophoneActivitySource, @unchecked Sendable {
    private let deviceInventory: any AudioInputDeviceInventory
    private let lock = NSLock()
    private var devices: [any AudioInputDevice] = []
    private var cachedIsActive = false

    init(deviceInventory: any AudioInputDeviceInventory = CoreAudioInputDeviceInventory()) {
        self.deviceInventory = deviceInventory
        refreshDevices()
    }

    func isMicrophoneActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedIsActive
    }

    func refreshDevices() {
        do {
            let nextDevices = try deviceInventory.inputDevices()
            nextDevices.forEach { device in
                try? device.installRunningListener { [weak self] in
                    self?.refreshCachedState()
                }
            }

            lock.lock()
            devices = nextDevices
            lock.unlock()
            refreshCachedState()
        } catch {
            lock.lock()
            devices = []
            cachedIsActive = false
            lock.unlock()
        }
    }

    private func refreshCachedState() {
        lock.lock()
        let currentDevices = devices
        lock.unlock()

        let nextValue = (try? currentDevices.contains { try $0.isRunningSomewhere() }) ?? false

        lock.lock()
        cachedIsActive = nextValue
        lock.unlock()
    }
}
```

- [ ] **Step 5: Add test doubles that exercise the source without real CoreAudio**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct StubAudioInputDeviceInventory: AudioInputDeviceInventory {
    let devices: [StubAudioInputDevice]

    func inputDevices() throws -> [AudioInputDevice] {
        devices
    }
}

struct FailingAudioInputDeviceInventory: AudioInputDeviceInventory {
    func inputDevices() throws -> [AudioInputDevice] {
        throw CocoaError(.fileReadUnknown)
    }
}

final class StubAudioInputDevice: AudioInputDevice, @unchecked Sendable {
    let id: String
    private let runningSomewhere: Bool

    init(id: String, isRunningSomewhere: Bool) {
        self.id = id
        self.runningSomewhere = isRunningSomewhere
    }

    func isRunningSomewhere() throws -> Bool {
        runningSomewhere
    }

    func installRunningListener(_ onChange: @escaping @Sendable () -> Void) throws {
        _ = onChange
    }
}
```

- [ ] **Step 6: Re-run the microphone-source tests and verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeMicrophoneActivitySourceTests`

Expected: PASS for `returnsTrueWhenAnyInputDeviceReportsRunning` and `returnsFalseWhenEnumerationFails`.

- [ ] **Step 7: Commit the microphone source slice**

```bash
git add QuickMeeting/Services/AutoRecording/MicrophoneActivitySource.swift QuickMeeting/Services/AutoRecording/NativeMicrophoneActivitySource.swift QuickMeetingTests/NativeMicrophoneActivitySourceTests.swift
git commit -m "feat: add microphone activity source"
```

### Task 3: Combine microphone state with app visibility and recent focus

**Files:**
- Modify: `QuickMeeting/Services/AutoRecording/NativeMeetingAppActivitySource.swift`
- Create: `QuickMeetingTests/NativeMeetingAppActivitySourceTests.swift`

- [ ] **Step 1: Write the failing app-activity tests for recent focus and microphone gating**

```swift
import AppKit
import Foundation
import Testing
@testable import QuickMeeting

struct NativeMeetingAppActivitySourceTests {
    @Test
    func keepsRecentFocusTrueForThirtySecondsAfterFrontmostLoss() {
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 100))
        let microphone = StubMicrophoneActivitySource(isActive: true)
        let source = NativeMeetingAppActivitySource(
            workspace: .shared,
            runningApplications: {
                [StubRunningApplication(bundleIdentifier: "kontur.talk").nsRunningApplication]
            },
            frontmostBundleIdentifier: { nil },
            visibleWindowBundleIdentifiers: { ["kontur.talk"] },
            microphoneActivitySource: microphone,
            now: { clock.now },
            recentFocusWindow: 30
        )

        source.noteFrontmostApp(bundleIdentifier: "kontur.talk")
        clock.now = Date(timeIntervalSinceReferenceDate: 125)

        let sample = source.sample(for: .tolk)
        #expect(sample.hadRecentFocus == true)
        #expect(sample.isMicrophoneActive == true)
    }

    @Test
    func returnsInactiveSignalsWhenMicrophoneIsOff() {
        let source = NativeMeetingAppActivitySource(
            workspace: .shared,
            runningApplications: {
                [StubRunningApplication(bundleIdentifier: "kontur.talk").nsRunningApplication]
            },
            frontmostBundleIdentifier: { "kontur.talk" },
            visibleWindowBundleIdentifiers: { ["kontur.talk"] },
            microphoneActivitySource: StubMicrophoneActivitySource(isActive: false),
            now: Date.init,
            recentFocusWindow: 30
        )

        let sample = source.sample(for: .tolk)
        #expect(sample.isRunning == true)
        #expect(sample.hasVisibleWindow == true)
        #expect(sample.isMicrophoneActive == false)
    }
}
```

- [ ] **Step 2: Run the targeted app-activity tests and verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeMeetingAppActivitySourceTests`

Expected: FAIL because `NativeMeetingAppActivitySource` does not inject microphone state or retain recent focus timestamps.

- [ ] **Step 3: Expand the activity source with time-based focus tracking and injected visibility providers**

```swift
import AppKit
import Foundation

struct NativeMeetingAppActivitySource: MeetingAppActivitySource {
    private let workspace: NSWorkspace
    private let runningApplications: () -> [NSRunningApplication]
    private let frontmostBundleIdentifier: () -> String?
    private let visibleWindowBundleIdentifiers: () -> Set<String>
    private let microphoneActivitySource: any MicrophoneActivitySource
    private let now: () -> Date
    private let recentFocusWindow: TimeInterval
    private var lastFocusedAtByBundleIdentifier: [String: Date] = [:]

    init(
        workspace: NSWorkspace = .shared,
        runningApplications: @escaping () -> [NSRunningApplication] = {
            NSWorkspace.shared.runningApplications
        },
        frontmostBundleIdentifier: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        visibleWindowBundleIdentifiers: @escaping () -> Set<String> = Self.visibleWindowBundleIdentifiers,
        microphoneActivitySource: any MicrophoneActivitySource = NativeMicrophoneActivitySource(),
        now: @escaping () -> Date = Date.init,
        recentFocusWindow: TimeInterval = 30
    ) {
        self.workspace = workspace
        self.runningApplications = runningApplications
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.visibleWindowBundleIdentifiers = visibleWindowBundleIdentifiers
        self.microphoneActivitySource = microphoneActivitySource
        self.now = now
        self.recentFocusWindow = recentFocusWindow
    }

    mutating func noteFrontmostApp(bundleIdentifier: String?) {
        guard let bundleIdentifier else { return }
        lastFocusedAtByBundleIdentifier[bundleIdentifier] = now()
    }

    mutating func sample(for app: AutoRecordingApp) -> MeetingAppActivitySample {
        let bundleIdentifier = bundleIdentifier(for: app)
        noteFrontmostApp(bundleIdentifier: frontmostBundleIdentifier())

        let isRunning = runningApplications().contains { $0.bundleIdentifier == bundleIdentifier }
        let isFrontmost = frontmostBundleIdentifier() == bundleIdentifier
        let hasVisibleWindow = visibleWindowBundleIdentifiers().contains(bundleIdentifier)
        let hadRecentFocus = lastFocusedAtByBundleIdentifier[bundleIdentifier].map {
            now().timeIntervalSince($0) <= recentFocusWindow
        } ?? false

        return MeetingAppActivitySample(
            bundleIdentifier: bundleIdentifier,
            isRunning: isRunning,
            isFrontmost: isFrontmost,
            hadRecentFocus: hadRecentFocus,
            hasVisibleWindow: hasVisibleWindow,
            isMicrophoneActive: microphoneActivitySource.isMicrophoneActive()
        )
    }
}
```

- [ ] **Step 4: Add simple test doubles for microphone state and time**

```swift
import Foundation
@testable import QuickMeeting

final class StubMicrophoneActivitySource: MicrophoneActivitySource, @unchecked Sendable {
    var isActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
    }

    func isMicrophoneActive() -> Bool {
        isActive
    }
}

final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
```

- [ ] **Step 5: Re-run the app-activity tests and verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeMeetingAppActivitySourceTests`

Expected: PASS for recent-focus retention and microphone-state propagation.

- [ ] **Step 6: Commit the app-activity integration**

```bash
git add QuickMeeting/Services/AutoRecording/NativeMeetingAppActivitySource.swift QuickMeetingTests/NativeMeetingAppActivitySourceTests.swift
git commit -m "feat: combine microphone and app activity signals"
```

### Task 4: Wire the new source into the app and lock the integration down

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `docs/quickmeeting-architecture-design.md`

- [ ] **Step 1: Add a focused integration test that proves auto-recording still reacts through the coordinator**

```swift
@Test
func autoRecordingStatusUpdatesForMicrophoneQualifiedPresence() async {
    let harness = AppViewModelHarness()

    await harness.viewModel.updateAutoRecordingPresence(.candidateActive)
    #expect(harness.viewModel.autoRecordingStatusText == "Detected meeting activity in Толк, waiting 10s")

    await harness.viewModel.updateAutoRecordingPresence(.ending)
    #expect(harness.viewModel.autoRecordingStatusText == "Meeting activity lost, stopping soon")

    await harness.viewModel.updateAutoRecordingPresence(.inactive)
    #expect(harness.viewModel.autoRecordingStatusText == nil)
}
```

- [ ] **Step 2: Run the smallest relevant integration slice**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests/autoRecordingStatusUpdatesForMicrophoneQualifiedPresence -only-testing:QuickMeetingTests/MeetingPresenceDetectorTests -only-testing:QuickMeetingTests/NativeMeetingAppActivitySourceTests -only-testing:QuickMeetingTests/NativeMicrophoneActivitySourceTests`

Expected: PASS for the new detector, activity-source, microphone-source, and status tests.

- [ ] **Step 3: Update the architecture doc so future work sees the new detector boundary**

```markdown
- Auto recording now treats active microphone usage as a required signal and combines it with selected-app visibility or recent focus before scheduling recording.
- CoreAudio-backed microphone state lives in `Services/AutoRecording/NativeMicrophoneActivitySource.swift`.
- Selected-app sampling and recent-focus tracking live in `Services/AutoRecording/NativeMeetingAppActivitySource.swift`.
```

- [ ] **Step 4: Commit the test and docs alignment**

```bash
git add QuickMeetingTests/AppViewModelTests.swift docs/quickmeeting-architecture-design.md
git commit -m "test: cover microphone-aware auto recording flow"
```

## Self-Review

### Spec coverage

- Microphone-required detection rule: covered in Task 1.
- CoreAudio-backed microphone source: covered in Task 2.
- Selected-app visibility and recent-focus window: covered in Task 3.
- Fail-closed behavior when microphone state cannot be read: covered in Task 2 tests and implementation.
- Integration and documentation alignment: covered in Task 4.
- Deferred Bluetooth fallback: intentionally omitted from tasks to match the spec's non-goals.

### Placeholder scan

- No `TBD`, `TODO`, or deferred implementation markers remain in the plan.
- Every code-changing step includes a concrete code block.
- Every verification step includes a concrete command and expected result.

### Type consistency

- `MeetingAppActivitySample` consistently uses `isMicrophoneActive`.
- `MicrophoneActivitySource.isMicrophoneActive()` is used consistently in both tests and implementation.
- `NativeMeetingAppActivitySource.sample(for:)` remains the integration point consumed by `MeetingAppMonitor`.

## Execution Handoff

Plan written to [2026-05-14-microphone-aware-auto-recording.md](/Users/heymdall/Developer/QuickMeeting/docs/plans/2026-05-14-microphone-aware-auto-recording.md:1).

If you want, I can start executing this plan next. 
