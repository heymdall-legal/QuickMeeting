**Goal:** Add a stateful macOS menubar icon that stays unchanged while idle, shows a subtle badge while auto-recording is armed, and shows a stronger badge while QuickMeeting is actively recording.

**Architecture:** Keep the existing `AppViewModel -> MenuBarController -> NSStatusItem` flow, but add a narrow `MenuBarIconState` enum derived from explicit app state instead of from display text. Tighten the auto-recording integration by exposing a semantic "pending auto-record start" flag in `AppViewModel`, then build all icon variants from the existing `waveform.circle` symbol through a small AppKit image helper.

**Tech Stack:** Swift, SwiftUI, AppKit, Combine, Testing, xcodebuild

---

## File Structure

**Create:**
- `QuickMeeting/MenuBar/MenuBarIconState.swift`
- `QuickMeeting/MenuBar/MenuBarIconImageBuilder.swift`

**Modify:**
- `QuickMeeting/ViewModels/AppViewModel.swift`
- `QuickMeeting/MenuBar/MenuBarController.swift`
- `QuickMeetingTests/AppViewModelTests.swift`

**Why these files:**
- `QuickMeeting/MenuBar/MenuBarIconState.swift` keeps menubar icon logic isolated from recording business logic.
- `QuickMeeting/MenuBar/MenuBarIconImageBuilder.swift` gives one focused place to build the idle, pending, and recording icon variants.
- `QuickMeeting/ViewModels/AppViewModel.swift` is already the UI-facing integration point for recording state and auto-recording lifecycle.
- `QuickMeeting/MenuBar/MenuBarController.swift` already owns the `NSStatusItem`, so it should stay responsible for applying icon updates.
- `QuickMeetingTests/AppViewModelTests.swift` already covers auto-recording status behavior and is the cheapest place to lock down the new semantic state mapping before touching AppKit.

### Task 1: Add a semantic menubar icon state to `AppViewModel`

**Files:**
- Create: `QuickMeeting/MenuBar/MenuBarIconState.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Add failing tests for the new icon-state mapping**

```swift
    @Test
    func menuBarIconStateIsIdleByDefault() throws {
        let harness = try AppViewModelTestHarness()
        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions
        )

        #expect(viewModel.menuBarIconState == .idle)
    }

    @Test
    func menuBarIconStateBecomesPendingWhenMeetingActivityIsDetected() async throws {
        let harness = try AppViewModelTestHarness()
        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions
        )

        await viewModel.updateAutoRecordingPresence(.candidateActive)

        #expect(viewModel.menuBarIconState == .pendingAutoRecord)
    }

    @Test
    func menuBarIconStateBecomesRecordingWhileManualRecordingIsActive() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        var meetingIDs = [meetingID]
        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        await viewModel.startRecording()

        #expect(viewModel.menuBarIconState == .recording)
    }

    @Test
    func menuBarIconStatePrefersRecordingOverPendingAutoRecord() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        var meetingIDs = [meetingID]
        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        await viewModel.updateAutoRecordingPresence(.candidateActive)
        await viewModel.startRecording()

        #expect(viewModel.menuBarIconState == .recording)
    }
```

- [ ] **Step 2: Run the focused view-model tests and verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: FAIL because `menuBarIconState` and `pendingAutoRecordingStart` do not exist yet.

- [ ] **Step 3: Add the new menubar icon enum**

```swift
import Foundation

enum MenuBarIconState: Equatable {
    case idle
    case pendingAutoRecord
    case recording
}
```

- [ ] **Step 4: Add explicit pending-auto-record state and derived icon mapping to `AppViewModel`**

```swift
    @Published private(set) var autoRecordingStatusText: String?
    @Published private(set) var isAutoRecordingStartPending = false

    var menuBarIconState: MenuBarIconState {
        switch recordingState {
        case .recording, .stopping:
            return .recording
        case .idle, .starting, .failed:
            return isAutoRecordingStartPending ? .pendingAutoRecord : .idle
        }
    }
```

```swift
    func updateAutoRecordingPresence(_ presence: MeetingAppPresence) async {
        switch presence {
        case .candidateActive, .activeMeeting:
            isAutoRecordingStartPending = !canStopRecording
            autoRecordingStatusText = "Detected meeting activity, waiting 10s"
        case .ending:
            isAutoRecordingStartPending = false
            autoRecordingStatusText = "Meeting activity lost, stopping soon"
        case .inactive:
            isAutoRecordingStartPending = false
            autoRecordingStatusText = nil
        }

        await autoRecordingCoordinator?.handle(presence)
    }
```

```swift
    func requestAutoRecordingStart() async {
        guard canStartRecording else {
            isAutoRecordingStartPending = false
            return
        }

        isAutoRecordingStartPending = false
        autoRecordingStatusText = "Recording started automatically"
        await startRecording()

        if case .recording = recordingState {
            autoRecordingCoordinator?.recordingDidStart()
        }
    }
```

```swift
    func requestAutoRecordingStop() async {
        isAutoRecordingStartPending = false

        guard canStopRecording else {
            return
        }

        await stopRecording()

        if case .idle = recordingState {
            autoRecordingStatusText = nil
        }
    }
```

- [ ] **Step 5: Re-run the focused view-model tests and verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: PASS, including the new `menuBarIconState` assertions.

- [ ] **Step 6: Commit the semantic icon-state plumbing**

```bash
git add QuickMeeting/MenuBar/MenuBarIconState.swift QuickMeeting/ViewModels/AppViewModel.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: expose menubar icon state from app view model"
```

### Task 2: Build the three menubar icon variants from one base symbol

**Files:**
- Create: `QuickMeeting/MenuBar/MenuBarIconImageBuilder.swift`

- [ ] **Step 1: Add the AppKit image builder**

```swift
import AppKit

enum MenuBarIconImageBuilder {
    static func makeImage(for state: MenuBarIconState) -> NSImage? {
        switch state {
        case .idle:
            return configuredSymbol(named: "waveform.circle")
        case .pendingAutoRecord:
            return configuredSymbol(named: "waveform.circle.badge.exclamationmark")
        case .recording:
            return configuredSymbol(named: "waveform.circle.fill")
        }
    }

    private static func configuredSymbol(named symbolName: String) -> NSImage? {
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "QuickMeeting"
        )
        image?.isTemplate = false
        return image
    }
}
```

- [ ] **Step 2: Sanity-check that the symbols compile in app code**

Run: `xcodebuild build -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`

Expected: BUILD SUCCEEDED, proving the helper compiles before wiring it into the controller.

- [ ] **Step 3: Commit the image builder helper**

```bash
git add QuickMeeting/MenuBar/MenuBarIconImageBuilder.swift
git commit -m "feat: add menubar icon image builder"
```

### Task 3: Make `MenuBarController` react to view-model state changes

**Files:**
- Modify: `QuickMeeting/MenuBar/MenuBarController.swift`

- [ ] **Step 1: Update `MenuBarController` to observe the derived icon state**

```swift
import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: AppViewModel) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 220, height: 120)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(viewModel: viewModel)
        )

        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.target = self
        applyIconState(viewModel.menuBarIconState)

        viewModel.$recordingState
            .sink { [weak self, weak viewModel] _ in
                guard let self, let viewModel else {
                    return
                }

                self.applyIconState(viewModel.menuBarIconState)
            }
            .store(in: &cancellables)

        viewModel.$isAutoRecordingStartPending
            .sink { [weak self, weak viewModel] _ in
                guard let self, let viewModel else {
                    return
                }

                self.applyIconState(viewModel.menuBarIconState)
            }
            .store(in: &cancellables)
    }

    private func applyIconState(_ state: MenuBarIconState) {
        statusItem.button?.image = MenuBarIconImageBuilder.makeImage(for: state)
    }
}
```

- [ ] **Step 2: Build the app and verify the controller wiring compiles**

Run: `xcodebuild build -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`

Expected: BUILD SUCCEEDED with no Combine or AppKit compile errors.

- [ ] **Step 3: Commit the status-item update flow**

```bash
git add QuickMeeting/MenuBar/MenuBarController.swift
git commit -m "feat: update menubar icon from recording state"
```

### Task 4: Verify the behavior end to end with targeted tests and a manual check

**Files:**
- Test: `QuickMeetingTests/AppViewModelTests.swift`
- Modify if needed: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify if needed: `QuickMeeting/MenuBar/MenuBarController.swift`

- [ ] **Step 1: Re-run the focused test suite for the final pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: PASS, including the new icon-state assertions and the existing auto-recording regression coverage.

- [ ] **Step 2: Build the app one more time for manual verification**

Run: `xcodebuild build -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manually verify the three visual states**

Run the app and confirm:

```text
1. Idle shows the existing QuickMeeting menubar icon with no badge.
2. Detected meeting activity during the auto-recording delay shows the pending badge.
3. Active recording shows the stronger recording badge.
```

- [ ] **Step 4: Commit any final polish from verification**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/MenuBar/MenuBarController.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "test: verify menubar status icon behavior"
```

## Self-Review

### Spec coverage

- Idle / pending / recording state mapping is covered by Task 1.
- Explicit semantic pending-start state instead of deriving from display copy is covered by Task 1.
- Shared menubar identity with one image-construction seam is covered by Task 2.
- `NSStatusItem` update flow stays inside `MenuBarController` in Task 3.
- Targeted tests plus manual validation are covered by Task 4.

### Placeholder scan

- No `TODO`, `TBD`, or "similar to above" placeholders remain.
- Each code-changing step includes concrete code snippets or commands.

### Type consistency

- `MenuBarIconState`, `isAutoRecordingStartPending`, and `menuBarIconState` are introduced once and used consistently across all tasks.
- `MenuBarIconImageBuilder.makeImage(for:)` is the only image-construction entry point used later in the plan.

## Execution Handoff

This plan is ready to execute from top to bottom with focused tests and small commits. If you want, I can start implementing it now.
