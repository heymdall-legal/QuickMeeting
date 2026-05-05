**Goal:** Add a detail-view delete flow that removes a meeting record and its local recording artifacts together.

**Architecture:** Keep the delete trigger in the detail UI, route the action through `ContentView`, and centralize delete rules plus error reporting in `AppViewModel`. Let `MeetingFileStore` own artifact cleanup so persistence and filesystem concerns stay separated.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, Foundation

---

### Task 1: Add artifact deletion coverage

**Files:**
- Modify: `QuickMeetingTests/MeetingFileStoreTests.swift`
- Modify: `QuickMeeting/Services/MeetingFileStore.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test
func deleteArtifactsRemovesMeetingFolderAndAudioFile() throws
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingFileStoreTests`
Expected: FAIL because `MeetingFileStore` has no delete API yet.

- [ ] **Step 3: Write minimal implementation**

```swift
func deleteArtifacts(for meeting: Meeting) throws
```

- [ ] **Step 4: Run test to verify it passes**

Run the same `xcodebuild test` command.
Expected: PASS.

### Task 2: Add view-model deletion behavior

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@Test
func deleteMeetingRemovesPersistedMeetingAndArtifacts() async throws

@Test
func deleteMeetingIgnoresTheActiveOrRecoverableMeeting() async throws
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`
Expected: FAIL because the delete API and delete-state reporting do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
func deleteMeeting(_ meeting: Meeting)
var deletionErrorMessage: String?
func canDeleteMeeting(_ meeting: Meeting) -> Bool
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same `xcodebuild test` command.
Expected: PASS.

### Task 3: Add the delete UI

**Files:**
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeeting/ContentView.swift`

- [ ] **Step 1: Write the view-facing behavior to support**

Add a destructive detail button, a confirmation alert, and an error alert hook.

- [ ] **Step 2: Implement the minimal UI**

Wire the detail button to the new view-model delete API and disable it when deletion is not allowed.

- [ ] **Step 3: Run focused verification**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingFileStoreTests -only-testing:QuickMeetingTests/AppViewModelTests`
Expected: PASS.

### Self-Review

- Spec coverage: UI trigger, confirmation, active-meeting guard, filesystem cleanup, and error handling are all represented in the tasks above.
- Placeholder scan: No `TODO` or implicit steps remain.
- Type consistency: The same delete API names are used across tests, view model, and UI tasks.
