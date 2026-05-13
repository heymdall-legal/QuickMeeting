**Goal:** Persist calendar attendee display names on `Meeting` when recording starts and a matching calendar event exists, while leaving the attendee list empty for unmatched or unauthorized starts.

**Architecture:** Reuse the existing recording-start calendar match in `AppViewModel` as the single place that resolves calendar-derived meeting metadata. Extend `Meeting` and `MeetingStore.createMeeting(...)` to persist a plain `[String]` attendee snapshot without introducing any later sync path or extra calendar lookup layer.

**Tech Stack:** Swift, SwiftData, EventKit-backed calendar integration, Swift Testing, Xcode/macOS test runner

---

### Task 1: Persist attendee names on `Meeting`

**Files:**
- Modify: `QuickMeetingTests/MeetingStoreTests.swift`
- Modify: `QuickMeeting/Models/Meeting.swift`
- Modify: `QuickMeeting/Services/MeetingStore.swift`

- [ ] **Step 1: Write the failing meeting-store persistence test**

```swift
@Test
func createMeetingPersistsAttendeeNamesAcrossFreshContext() throws {
    let schema = Schema([
        Meeting.self,
        PersistedTranscriptSpeaker.self,
        PersistedTranscriptSegment.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    let store = MeetingStore(modelContext: context)

    let folderURL = URL(fileURLWithPath: "/tmp/meeting")
    let audioFileURL = folderURL.appendingPathComponent("audio.m4a")

    let meeting = try store.createMeeting(
        title: "Design Review",
        startedAt: Date(timeIntervalSince1970: 1_234_567_890),
        attendeeNames: ["Masha", "Ilya"],
        folderURL: folderURL,
        audioFileURL: audioFileURL
    )

    #expect(meeting.attendeeNames == ["Masha", "Ilya"])

    let verificationContext = ModelContext(container)
    let persistedMeeting = try #require(try verificationContext.fetch(FetchDescriptor<Meeting>()).first)
    #expect(persistedMeeting.attendeeNames == ["Masha", "Ilya"])
}
```

- [ ] **Step 2: Run the focused meeting-store test to verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests/createMeetingPersistsAttendeeNamesAcrossFreshContext`
Expected: FAIL because `createMeeting(...)` and `Meeting` do not yet support `attendeeNames`.

- [ ] **Step 3: Write the minimal persistence implementation**

```swift
@Model
final class Meeting {
    private(set) var attendeeNames: [String]

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        status: MeetingStatus,
        audioFilePath: String,
        transcriptFilePath: String? = nil,
        transcriptPreview: String? = nil,
        transcriptSpeakers: [PersistedTranscriptSpeaker] = [],
        transcriptSegments: [PersistedTranscriptSegment] = [],
        duration: TimeInterval? = nil,
        calendarEventID: String? = nil,
        attendeeNames: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.attendeeNames = attendeeNames
    }
}

@discardableResult
func createMeeting(
    id: UUID = UUID(),
    title: String,
    startedAt: Date,
    attendeeNames: [String] = [],
    folderURL: URL,
    audioFileURL: URL
) throws -> Meeting {
    let meeting = Meeting(
        id: id,
        title: title,
        startedAt: startedAt,
        status: .recording,
        audioFilePath: normalizedAudioFileURL.path(percentEncoded: false),
        attendeeNames: attendeeNames,
        createdAt: now,
        updatedAt: now
    )
}
```

- [ ] **Step 4: Run the focused meeting-store test to verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests/createMeetingPersistsAttendeeNamesAcrossFreshContext`
Expected: PASS.

- [ ] **Step 5: Commit the persistence slice**

```bash
git add QuickMeeting/Models/Meeting.swift QuickMeeting/Services/MeetingStore.swift QuickMeetingTests/MeetingStoreTests.swift
git commit -m "feat: persist meeting attendee names"
```

### Task 2: Populate attendee names from the matched event at recording start

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`

- [ ] **Step 1: Write the failing matched-event recording-start test**

```swift
@Test
func startRecordingPersistsAttendeeNamesFromMatchingCalendarEvent() async throws {
    let harness = try AppViewModelTestHarness()
    let meetingID = UUID()
    let startedAt = Date(timeIntervalSince1970: 1_746_692_100)
    var meetingIDs = [meetingID]
    let viewModel = AppViewModel(
        meetingStore: harness.meetingStore,
        meetingFileStore: harness.meetingFileStore,
        recordingService: harness.recordingService,
        recordingPermissions: harness.recordingPermissions,
        calendarIntegration: StubCalendarIntegration(
            matchingEvent: UpcomingCalendarEvent(
                title: "Design Review",
                startDate: startedAt.addingTimeInterval(300),
                endDate: startedAt.addingTimeInterval(2_100),
                attendees: [
                    UpcomingCalendarAttendee(displayName: "Masha", emailAddress: "masha@example.com"),
                    UpcomingCalendarAttendee(displayName: "Ilya", emailAddress: nil),
                ]
            )
        ),
        dateProvider: { startedAt },
        meetingIDProvider: { meetingIDs.removeFirst() }
    )

    await viewModel.startRecording()

    let persistedMeeting = try #require(try harness.context.fetch(FetchDescriptor<Meeting>()).first)
    #expect(persistedMeeting.title == "Design Review")
    #expect(persistedMeeting.attendeeNames == ["Masha", "Ilya"])
}
```

- [ ] **Step 2: Run the focused app-view-model test to verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests/startRecordingPersistsAttendeeNamesFromMatchingCalendarEvent`
Expected: FAIL because `startRecording()` only persists the matched title today.

- [ ] **Step 3: Write the minimal recording-start implementation**

```swift
func startRecording() async {
    let startedAt = dateProvider()
    let matchingEvent = calendarIntegration.eventMatchingRecordingStart(at: startedAt)

    let meeting = try meetingStore.createMeeting(
        id: meetingID,
        title: resolvedMeetingTitle(for: startedAt, matchingEvent: matchingEvent),
        startedAt: startedAt,
        attendeeNames: matchingEvent?.attendees.map(\.displayName) ?? [],
        folderURL: artifacts.meetingFolderURL,
        audioFileURL: artifacts.audioFileURL
    )
}

private func resolvedMeetingTitle(
    for startedAt: Date,
    matchingEvent: UpcomingCalendarEvent?
) -> String {
    if let matchingEvent {
        return matchingEvent.title
    }

    return meetingTitleFormatter.string(from: startedAt)
}
```

- [ ] **Step 4: Run the focused app-view-model test to verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests/startRecordingPersistsAttendeeNamesFromMatchingCalendarEvent`
Expected: PASS.

- [ ] **Step 5: Commit the recording-start attendee wiring**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: attach calendar attendees at recording start"
```

### Task 3: Guard the unmatched fallback behavior

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing fallback test**
- [ ] **Step 1: Add the fallback regression test**

```swift
@Test
func startRecordingPersistsEmptyAttendeeNamesWithoutCalendarMatch() async throws {
    let harness = try AppViewModelTestHarness()
    let meetingID = UUID()
    let startedAt = Date(timeIntervalSince1970: 1_746_692_100)
    var meetingIDs = [meetingID]
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    let viewModel = AppViewModel(
        meetingStore: harness.meetingStore,
        meetingFileStore: harness.meetingFileStore,
        recordingService: harness.recordingService,
        recordingPermissions: harness.recordingPermissions,
        calendarIntegration: StubCalendarIntegration(matchingEvent: nil),
        dateProvider: { startedAt },
        meetingIDProvider: { meetingIDs.removeFirst() },
        meetingTitleFormatter: formatter
    )

    await viewModel.startRecording()

    let persistedMeeting = try #require(try harness.context.fetch(FetchDescriptor<Meeting>()).first)
    #expect(persistedMeeting.title == formatter.string(from: startedAt))
    #expect(persistedMeeting.attendeeNames.isEmpty)
}
```

- [ ] **Step 2: Run the focused fallback test to verify it fails for the new behavior**
- [ ] **Step 2: Run the focused fallback test to verify the fallback stays green**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests/startRecordingPersistsEmptyAttendeeNamesWithoutCalendarMatch`
Expected: PASS, proving the unmatched path still persists an empty attendee list while keeping the timestamp fallback title.

- [ ] **Step 3: If the fallback test fails, adjust the implementation minimally until the fallback behavior is explicit**

```swift
let persistedMeeting = try #require(try harness.context.fetch(FetchDescriptor<Meeting>()).first)
#expect(persistedMeeting.title == formatter.string(from: startedAt))
#expect(persistedMeeting.attendeeNames == [])
```

- [ ] **Step 4: Run the focused attendee-related test set**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/AppViewModelTests`
Expected: PASS for the attendee persistence tests and no regressions in the existing recording-start coverage.

- [ ] **Step 5: Commit the completed attendee feature**

```bash
git add QuickMeetingTests/AppViewModelTests.swift
git commit -m "test: cover unmatched meeting attendee fallback"
```
