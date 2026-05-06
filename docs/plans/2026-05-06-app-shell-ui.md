**Goal:** Rework the main QuickMeeting window into a unified sidebar shell with `Home`, `Settings`, and `History`, while preserving current meeting detail and settings behavior.

**Architecture:** Keep one top-level `NavigationSplitView` in `ContentView`, replace the meeting-only selection with a small shell selection enum, and route the detail pane between a new `HomeView`, the existing `ModelsSettingsView`, and the existing `MeetingDetailView`. Extract the sidebar and shell-selection logic into focused units so the navigation rules can be tested without coupling them to recording or persistence behavior.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, Xcode

---

## File Structure

- Create: `QuickMeeting/Models/AppSidebarSelection.swift`
  - Defines the sidebar selection enum used by the unified shell.
- Create: `QuickMeeting/Views/HomeView.swift`
  - Holds the new recording control screen for the `Home` destination.
- Create: `QuickMeeting/Views/AppSidebarView.swift`
  - Renders the untitled `Home` and `Settings` items plus the `History` meeting section.
- Create: `QuickMeeting/Support/ContentViewSelectionState.swift`
  - Contains small pure helper functions for default selection and fallback selection rules so they can be tested directly.
- Create: `QuickMeetingTests/ContentViewSelectionStateTests.swift`
  - Verifies default selection, invalid meeting fallback, and non-pinning behavior.
- Modify: `QuickMeeting/ContentView.swift`
  - Converts the app shell to unified navigation and removes toolbar controls from the main window.
- Modify: `QuickMeeting/QuickMeetingApp.swift`
  - Passes `ModelsSettingsViewModel` into `ContentView` while preserving the standalone Settings scene.
- Optionally modify: `QuickMeeting/Views/RecordingToolbarControls.swift`
  - Remove the file if it becomes unused, or leave it untouched until a follow-up cleanup commit.

### Task 1: Add shell selection model and selection-state tests

**Files:**
- Create: `QuickMeeting/Models/AppSidebarSelection.swift`
- Create: `QuickMeeting/Support/ContentViewSelectionState.swift`
- Create: `QuickMeetingTests/ContentViewSelectionStateTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct ContentViewSelectionStateTests {
    @Test
    func defaultSelectionIsHome() {
        #expect(defaultSidebarSelection() == .home)
    }

    @Test
    func selectedMeetingRemainsWhenItStillExists() {
        let meetingID = UUID()

        let selection = reconciledSidebarSelection(
            currentSelection: .meeting(meetingID),
            availableMeetingIDs: [meetingID]
        )

        #expect(selection == .meeting(meetingID))
    }

    @Test
    func missingSelectedMeetingFallsBackToHome() {
        let selection = reconciledSidebarSelection(
            currentSelection: .meeting(UUID()),
            availableMeetingIDs: []
        )

        #expect(selection == .home)
    }

    @Test
    func nonMeetingSelectionIsUnaffectedByMeetingChanges() {
        let selection = reconciledSidebarSelection(
            currentSelection: .settings,
            availableMeetingIDs: []
        )

        #expect(selection == .settings)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-app-shell-plan "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/ContentViewSelectionStateTests
```

Expected: FAIL with errors that `defaultSidebarSelection`, `reconciledSidebarSelection`, and `AppSidebarSelection` do not exist yet.

- [ ] **Step 3: Write the minimal implementation**

`QuickMeeting/Models/AppSidebarSelection.swift`

```swift
import Foundation

enum AppSidebarSelection: Hashable {
    case home
    case settings
    case meeting(UUID)
}
```

`QuickMeeting/Support/ContentViewSelectionState.swift`

```swift
import Foundation

func defaultSidebarSelection() -> AppSidebarSelection {
    .home
}

func reconciledSidebarSelection(
    currentSelection: AppSidebarSelection,
    availableMeetingIDs: [UUID]
) -> AppSidebarSelection {
    switch currentSelection {
    case .meeting(let meetingID):
        return availableMeetingIDs.contains(meetingID) ? .meeting(meetingID) : .home
    case .home, .settings:
        return currentSelection
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-app-shell-plan "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/ContentViewSelectionStateTests
```

Expected: PASS for 4 tests in `ContentViewSelectionStateTests`.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Models/AppSidebarSelection.swift QuickMeeting/Support/ContentViewSelectionState.swift QuickMeetingTests/ContentViewSelectionStateTests.swift
git commit -m "test: add app shell selection state coverage"
```

### Task 2: Build the new `Home` destination

**Files:**
- Create: `QuickMeeting/Views/HomeView.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Add a small preview-first view implementation**

`QuickMeeting/Views/HomeView.swift`

```swift
import SwiftUI

struct HomeView: View {
    @ObservedObject var appViewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Home")
                .font(.title2.weight(.semibold))

            Text(statusText)
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await appViewModel.startRecording()
                    }
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appViewModel.canStartRecording)

                Button {
                    Task {
                        await appViewModel.stopRecording()
                    }
                } label: {
                    Label("Stop Recording", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
                .disabled(!appViewModel.canStopRecording)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .navigationTitle("Home")
    }

    private var statusText: String {
        switch appViewModel.recordingState {
        case .idle:
            return "Ready"
        case .starting:
            return "Starting recording..."
        case .recording:
            return "Recording in progress"
        case .stopping:
            return "Stopping recording..."
        case .failed(let message):
            return message
        }
    }
}
```

- [ ] **Step 2: Verify the existing recording-state tests still pass unchanged**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-app-shell-plan "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS. No new `AppViewModel` behavior should be required for the `Home` screen.

- [ ] **Step 3: Commit**

```bash
git add QuickMeeting/Views/HomeView.swift
git commit -m "feat: add home recording view"
```

### Task 3: Build the unified sidebar view

**Files:**
- Create: `QuickMeeting/Views/AppSidebarView.swift`
- Modify: `QuickMeeting/Views/MeetingListView.swift`

- [ ] **Step 1: Write the new sidebar view**

`QuickMeeting/Views/AppSidebarView.swift`

```swift
import SwiftUI

struct AppSidebarView: View {
    let meetings: [Meeting]
    @Binding var selection: AppSidebarSelection

    var body: some View {
        List(selection: $selection) {
            Label("Home", systemImage: "house")
                .tag(AppSidebarSelection.home)

            Label("Settings", systemImage: "gearshape")
                .tag(AppSidebarSelection.settings)

            Section("History") {
                ForEach(meetings) { meeting in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                            .font(.headline)

                        Text(
                            meeting.startedAt,
                            format: .dateTime.month(.abbreviated).day().hour().minute()
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .tag(AppSidebarSelection.meeting(meeting.id))
                }
            }
        }
        .navigationTitle("QuickMeeting")
    }
}
```

- [ ] **Step 2: Remove the old meeting-only sidebar view once the new one compiles**

Delete the `MeetingListView` usage path from the app. If the type is now unused, either:

- delete `QuickMeeting/Views/MeetingListView.swift`, or
- keep it only if another target still references it

If deleting the file, use this replacement plan:

```swift
// No replacement file content. Remove MeetingListView.swift from the target after AppSidebarView is wired in.
```

- [ ] **Step 3: Run a build-focused test pass**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-app-shell-plan "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/ContentViewSelectionStateTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS. This confirms the new sidebar view compiles cleanly without changing recording behavior.

- [ ] **Step 4: Commit**

```bash
git add QuickMeeting/Views/AppSidebarView.swift QuickMeeting/Views/MeetingListView.swift
git commit -m "feat: add unified app sidebar"
```

### Task 4: Rework `ContentView` into the unified shell

**Files:**
- Modify: `QuickMeeting/ContentView.swift`

- [ ] **Step 1: Replace the meeting-only shell with the approved destination router**

Use this structure inside `ContentView`:

```swift
import SwiftData
import SwiftUI

struct ContentView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var modelsViewModel: ModelsSettingsViewModel
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @State private var selection: AppSidebarSelection = defaultSidebarSelection()

    var body: some View {
        NavigationSplitView {
            AppSidebarView(meetings: meetings, selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            switch selection {
            case .home:
                HomeView(appViewModel: appViewModel)
            case .settings:
                ModelsSettingsView(viewModel: modelsViewModel)
            case .meeting(let meetingID):
                if let selectedMeeting = meetings.first(where: { $0.id == meetingID }) {
                    MeetingDetailView(
                        meeting: selectedMeeting,
                        canDelete: appViewModel.canDeleteMeeting(selectedMeeting),
                        canTranscribe: appViewModel.canTranscribeMeeting(selectedMeeting),
                        onTranscribe: {
                            Task {
                                await appViewModel.transcribeMeeting(selectedMeeting)
                            }
                        },
                        onDelete: {
                            appViewModel.deleteMeeting(selectedMeeting)
                        }
                    )
                } else {
                    HomeView(appViewModel: appViewModel)
                }
            }
        }
        .onAppear {
            selection = reconciledSidebarSelection(
                currentSelection: selection,
                availableMeetingIDs: meetings.map(\.id)
            )
        }
        .onChange(of: meetings.map(\.id)) { _, updatedMeetingIDs in
            selection = reconciledSidebarSelection(
                currentSelection: selection,
                availableMeetingIDs: updatedMeetingIDs
            )
        }
    }
}
```

- [ ] **Step 2: Re-add the existing alerts exactly as they work today**

Keep the current bindings and alert blocks for:

- deletion failures
- transcription failures

Do not reintroduce `.toolbar { RecordingToolbarControls(...) }`.

- [ ] **Step 3: Update the preview to pass both view models**

Use this preview shape:

```swift
#Preview {
    let container = previewModelContainer()

    ContentView(
        appViewModel: previewAppViewModel(container: container),
        modelsViewModel: previewModelsSettingsViewModel()
    )
    .modelContainer(container)
}
```

Also add:

```swift
@MainActor
private func previewModelsSettingsViewModel() -> ModelsSettingsViewModel {
    ModelsSettingsViewModel(
        manager: TranscriptionModelManager(
            modelStore: ArgmaxWhisperModelStore(),
            settingsStore: ModelSettingsStore()
        )
    )
}
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-app-shell-plan "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/ContentViewSelectionStateTests -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/ModelsSettingsViewModelTests
```

Expected: PASS. This confirms shell state, recording behavior, and settings model loading still build and test together.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/ContentView.swift
git commit -m "feat: route main window through unified shell"
```

### Task 5: Wire the app entry point and preserve the standalone Settings scene

**Files:**
- Modify: `QuickMeeting/QuickMeetingApp.swift`

- [ ] **Step 1: Pass `modelsSettingsViewModel` into the main content view**

Update the `WindowGroup` body to:

```swift
WindowGroup {
    ContentView(
        appViewModel: appViewModel,
        modelsViewModel: modelsSettingsViewModel
    )
    .task {
        if menuBarController == nil {
            menuBarController = MenuBarController(viewModel: appViewModel)
        }
    }
}
```

- [ ] **Step 2: Leave the Settings scene untouched except for compile fixes**

Keep:

```swift
Settings {
    SettingsView(modelsViewModel: modelsSettingsViewModel)
}
```

The plan goal is to add settings to the main shell, not replace the macOS Settings scene.

- [ ] **Step 3: Run a full target test pass**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-app-shell-plan "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY="
```

Expected: PASS for the full `QuickMeetingTests` target.

- [ ] **Step 4: Commit**

```bash
git add QuickMeeting/QuickMeetingApp.swift
git commit -m "feat: expose settings in main app shell"
```

### Task 6: Cleanup and manual verification

**Files:**
- Modify or delete: `QuickMeeting/Views/RecordingToolbarControls.swift`
- Modify: `docs/plans/2026-05-06-app-shell-ui.md`

- [ ] **Step 1: Remove dead code if `RecordingToolbarControls` is unused**

If `rg "RecordingToolbarControls" QuickMeeting QuickMeetingTests` only shows its own file definition, delete the file and remove its target reference.

If the file is still referenced elsewhere, leave it in place for a later cleanup commit.

- [ ] **Step 2: Run a quick usage check**

Run:

```bash
rg "RecordingToolbarControls|MeetingListView" QuickMeeting QuickMeetingTests
```

Expected:

- no `RecordingToolbarControls` references from the main window
- no stale `MeetingListView` references if the type was removed

- [ ] **Step 3: Perform manual app verification**

Run:

```bash
xcodebuild build -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-app-shell-plan "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY="
```

Then verify manually:

- the app opens to `Home`
- `Start Recording` and `Stop Recording` appear on `Home`
- starting a recording does not navigate away from `Home`
- selecting `Settings` shows the models settings content
- selecting a meeting in `History` shows meeting details
- deleting the selected meeting returns the detail pane to `Home`

- [ ] **Step 4: Commit**

```bash
git add QuickMeeting/Views/RecordingToolbarControls.swift QuickMeeting/Views/MeetingListView.swift
git commit -m "refactor: remove obsolete shell views"
```

## Self-Review

Spec coverage:

- Unified `NavigationSplitView` shell: Tasks 3 and 4
- `Home` as default destination: Tasks 1 and 4
- `Settings` inside main window: Tasks 4 and 5
- `History` behavior preserved: Tasks 3 and 4
- No recording-driven auto-navigation: Tasks 1 and 4
- Fallback to `Home` when a meeting disappears: Tasks 1 and 4
- Toolbar recording controls removed from main window: Tasks 2, 4, and 6
- Standalone macOS Settings scene preserved: Task 5

Placeholder scan:

- No `TBD`, `TODO`, or deferred implementation language remains.
- Each code-changing step includes the concrete code shape to add or update.
- Each verification step includes the exact command and expected outcome.

Type consistency:

- Sidebar selection type is consistently named `AppSidebarSelection`.
- Selection helpers are consistently named `defaultSidebarSelection()` and `reconciledSidebarSelection(...)`.
- Main shell view consistently routes through `HomeView`, `ModelsSettingsView`, and `MeetingDetailView`.
