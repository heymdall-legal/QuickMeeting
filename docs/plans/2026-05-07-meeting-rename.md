**Goal:** Add inline meeting-title rename in the detail view with confirm-on-return or blur, escape-to-cancel, and persisted empty-title rejection.

**Architecture:** Keep edit-state and keyboard handling in `MeetingDetailView`, but enforce the actual rename rule in `MeetingStore` through `AppViewModel`. The model owns title mutation plus `updatedAt`, while the view model exposes rename error state for UI alerts.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing

---

### Task 1: Persisted Meeting Rename

**Files:**
- Modify: `QuickMeetingTests/MeetingStoreTests.swift`
- Modify: `QuickMeeting/Models/Meeting.swift`
- Modify: `QuickMeeting/Services/MeetingStore.swift`

- [ ] **Step 1: Write the failing test**

```swift
    @Test
    func renameMeetingUpdatesPersistedTitleAndUpdatedAt() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let renamedAt = Date(timeIntervalSince1970: 1_234_568_300)

        try harness.store.renameMeeting(
            meetingID: meeting.id,
            title: "Renamed Review",
            updatedAt: renamedAt
        )

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(reloaded.title == "Renamed Review")
        #expect(reloaded.updatedAt == renamedAt)
    }

    @Test
    func renameMeetingRejectsEmptyTrimmedTitle() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let originalUpdatedAt = meeting.updatedAt

        #expect(throws: MeetingStoreError.invalidMeetingTitle) {
            try harness.store.renameMeeting(
                meetingID: meeting.id,
                title: "   ",
                updatedAt: Date(timeIntervalSince1970: 1_234_568_300)
            )
        }

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(reloaded.title == "Design Review")
        #expect(reloaded.updatedAt == originalUpdatedAt)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests`
Expected: FAIL because `renameMeeting` and `invalidMeetingTitle` do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
enum MeetingStoreError: Error, Equatable {
    case audioFileOutsideRecordingFolder
    case meetingNotFound
    case invalidMeetingTitle
}

func renameTitle(to newTitle: String, updatedAt: Date = Date()) {
    title = newTitle
    touch(updatedAt: updatedAt)
}

func renameMeeting(meetingID: UUID, title: String, updatedAt: Date) throws {
    let meeting = try fetchMeeting(id: meetingID)
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !normalizedTitle.isEmpty else {
        throw MeetingStoreError.invalidMeetingTitle
    }

    meeting.renameTitle(to: normalizedTitle, updatedAt: updatedAt)
    try modelContext.save()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests`
Expected: PASS for the new rename coverage and no regressions in that test target.

- [ ] **Step 5: Commit**

```bash
git add QuickMeetingTests/MeetingStoreTests.swift QuickMeeting/Models/Meeting.swift QuickMeeting/Services/MeetingStore.swift
git commit -m "feat: persist meeting title rename"
```

### Task 2: View Model Rename Action

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`

- [ ] **Step 1: Write the failing test**

```swift
    @Test
    func renameMeetingPersistsTitleAndClearsPreviousError() async throws {
        let harness = try AppViewModelTestHarness()
        let meeting = try harness.createRecordedMeeting()
        let viewModel = harness.makeViewModel()

        try await viewModel.renameMeeting(meeting, title: "Renamed Review")

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(reloaded.title == "Renamed Review")
        #expect(viewModel.renameMeetingErrorMessage == nil)
    }

    @Test
    func renameMeetingStoresTheFailureMessageForUI() async throws {
        let harness = try AppViewModelTestHarness()
        let meeting = try harness.createRecordedMeeting()
        let viewModel = harness.makeViewModel()

        await #expect(throws: MeetingStoreError.invalidMeetingTitle) {
            try await viewModel.renameMeeting(meeting, title: "   ")
        }

        #expect(viewModel.renameMeetingErrorMessage == "The operation couldn’t be completed. (QuickMeeting.MeetingStoreError error 2.)")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`
Expected: FAIL because meeting rename API and error state do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
    @Published private(set) var renameMeetingErrorMessage: String?

    func renameMeeting(_ meeting: Meeting, title: String) async throws {
        do {
            try meetingStore.renameMeeting(
                meetingID: meeting.id,
                title: title,
                updatedAt: dateProvider()
            )
            renameMeetingErrorMessage = nil
        } catch {
            renameMeetingErrorMessage = error.localizedDescription
            throw error
        }
    }

    func clearRenameMeetingError() {
        renameMeetingErrorMessage = nil
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`
Expected: PASS with the new rename behavior covered.

- [ ] **Step 5: Commit**

```bash
git add QuickMeetingTests/AppViewModelTests.swift QuickMeeting/ViewModels/AppViewModel.swift
git commit -m "feat: add meeting rename action"
```

### Task 3: Inline Detail-View Editing

**Files:**
- Modify: `QuickMeeting/ContentView.swift`
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`

- [ ] **Step 1: Wire the view action**

```swift
                        onRenameMeeting: { title in
                            Task {
                                try? await appViewModel.renameMeeting(selectedMeeting, title: title)
                            }
                        },
```

- [ ] **Step 2: Add local edit state and callbacks**

```swift
    let onRenameMeeting: (String) -> Void

    @FocusState private var isTitleFieldFocused: Bool
    @State private var meetingTitleDraft = ""
    @State private var originalMeetingTitle = ""
```

- [ ] **Step 3: Replace the static title with an inline editor**

```swift
    private var editableTitleField: some View {
        TextField("Meeting title", text: $meetingTitleDraft)
            .textFieldStyle(.roundedBorder)
            .font(.title2.weight(.semibold))
            .focused($isTitleFieldFocused)
            .onSubmit(commitMeetingRename)
            .onExitCommand(perform: cancelMeetingRename)
            .onChange(of: isTitleFieldFocused) { _, isFocused in
                if !isFocused {
                    commitMeetingRename()
                }
            }
    }
```

- [ ] **Step 4: Add state sync and commit helpers**

```swift
    private func resetMeetingTitleDraft() {
        meetingTitleDraft = meeting.title
        originalMeetingTitle = meeting.title
    }

    private func commitMeetingRename() {
        let trimmedTitle = meetingTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            meetingTitleDraft = originalMeetingTitle
            return
        }

        guard trimmedTitle != originalMeetingTitle else {
            meetingTitleDraft = originalMeetingTitle
            return
        }

        onRenameMeeting(trimmedTitle)
        originalMeetingTitle = trimmedTitle
    }

    private func cancelMeetingRename() {
        meetingTitleDraft = originalMeetingTitle
        isTitleFieldFocused = false
    }
```

- [ ] **Step 5: Run targeted verification**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/AppViewModelTests`
Expected: PASS while the UI wiring compiles against the tested rename API.

- [ ] **Step 6: Commit**

```bash
git add QuickMeeting/ContentView.swift QuickMeeting/Views/MeetingDetailView.swift
git commit -m "feat: add inline meeting rename UI"
```
