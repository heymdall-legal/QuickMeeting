**Goal:** Add one-time automatic meeting naming at recording start using a matching calendar event when available, otherwise falling back to the `MM-dd HH:mm` timestamp format.

**Architecture:** Keep title selection in `AppViewModel.startRecording()` and make it deterministic by resolving the final title before persisting the meeting. Extend the calendar integration with a recording-start matching query, then use a small resolver helper in the app layer to combine that match with the fallback timestamp formatter.

**Tech Stack:** Swift, Swift Testing, SwiftData, EventKit

---

### Task 1: Calendar Matching Query

**Files:**
- Modify: `QuickMeeting/Services/Calendar/CalendarIntegration.swift`
- Modify: `QuickMeeting/Services/Calendar/NativeCalendarIntegration.swift`
- Test: `QuickMeetingTests/NativeCalendarIntegrationTests.swift`
- Test: `QuickMeetingTests/CalendarSettingsViewModelTests.swift`

- [ ] **Step 1: Write the failing calendar matching tests**

```swift
@Test
func eventMatchingRecordingStartUsesInclusiveMinusTenPlusFiveMinuteWindow() {
    let eventStore = FakeCalendarEventStore(
        authorizationState: .authorized,
        calendars: [CalendarDescriptor(id: "work", title: "Work")],
        events: [
            CalendarEvent(
                title: "Event A",
                startDate: Date(timeIntervalSince1970: 36_000),
                endDate: Date(timeIntervalSince1970: 37_800),
                isAllDay: false,
                calendarID: "work",
                attendees: []
            )
        ]
    )
    let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: ["work"])
    let integration = NativeCalendarIntegration(
        eventStore: eventStore,
        settingsStore: settingsStore,
        now: { Date(timeIntervalSince1970: 35_640) },
        calendar: Calendar(identifier: .gregorian)
    )

    #expect(integration.eventMatchingRecordingStart(at: Date(timeIntervalSince1970: 35_640)) == nil)
    #expect(integration.eventMatchingRecordingStart(at: Date(timeIntervalSince1970: 35_700))?.title == "Event A")
    #expect(integration.eventMatchingRecordingStart(at: Date(timeIntervalSince1970: 36_600))?.title == "Event A")
    #expect(integration.eventMatchingRecordingStart(at: Date(timeIntervalSince1970: 36_660)) == nil)
}

@Test
func eventMatchingRecordingStartReturnsFirstSortedMatchAndSkipsAllDayEvents() {
    let eventStore = FakeCalendarEventStore(
        authorizationState: .authorized,
        calendars: [CalendarDescriptor(id: "work", title: "Work")],
        events: [
            CalendarEvent(
                title: "All Day",
                startDate: Date(timeIntervalSince1970: 36_000),
                endDate: Date(timeIntervalSince1970: 72_000),
                isAllDay: true,
                calendarID: "work",
                attendees: []
            ),
            CalendarEvent(
                title: "Earlier Match",
                startDate: Date(timeIntervalSince1970: 35_850),
                endDate: Date(timeIntervalSince1970: 36_300),
                isAllDay: false,
                calendarID: "work",
                attendees: []
            ),
            CalendarEvent(
                title: "Later Match",
                startDate: Date(timeIntervalSince1970: 36_000),
                endDate: Date(timeIntervalSince1970: 36_900),
                isAllDay: false,
                calendarID: "work",
                attendees: []
            )
        ]
    )
    let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: ["work"])
    let integration = NativeCalendarIntegration(
        eventStore: eventStore,
        settingsStore: settingsStore,
        calendar: Calendar(identifier: .gregorian)
    )

    let event = integration.eventMatchingRecordingStart(at: Date(timeIntervalSince1970: 35_900))

    #expect(event?.title == "Earlier Match")
}

@Test
func eventMatchingRecordingStartReturnsNilWithoutPermissionOrSelection() {
    let denied = NativeCalendarIntegration(
        eventStore: FakeCalendarEventStore(
            authorizationState: .denied,
            calendars: [CalendarDescriptor(id: "work", title: "Work")],
            events: []
        ),
        settingsStore: InMemoryCalendarSelectionStore(selectedCalendarIDs: ["work"])
    )
    let noSelection = NativeCalendarIntegration(
        eventStore: FakeCalendarEventStore(
            authorizationState: .authorized,
            calendars: [CalendarDescriptor(id: "work", title: "Work")],
            events: []
        ),
        settingsStore: InMemoryCalendarSelectionStore(selectedCalendarIDs: [])
    )

    #expect(denied.eventMatchingRecordingStart(at: Date(timeIntervalSince1970: 36_000)) == nil)
    #expect(noSelection.eventMatchingRecordingStart(at: Date(timeIntervalSince1970: 36_000)) == nil)
}
```

- [ ] **Step 2: Run the calendar tests to verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeCalendarIntegrationTests -only-testing:QuickMeetingTests/CalendarSettingsViewModelTests`
Expected: FAIL because `eventMatchingRecordingStart(at:)` is not defined on `CalendarIntegration` and its stubs.

- [ ] **Step 3: Add the protocol and integration implementation**

```swift
protocol CalendarIntegration: Sendable {
    func authorizationState() -> CalendarAuthorizationState
    func requestAccess() async -> CalendarAuthorizationState
    func availableCalendars() -> [CalendarDescriptor]
    func upcomingEventForToday() -> UpcomingCalendarEvent?
    func eventMatchingRecordingStart(at startedAt: Date) -> UpcomingCalendarEvent?
}

func eventMatchingRecordingStart(at startedAt: Date) -> UpcomingCalendarEvent? {
    guard authorizationState() == .authorized else {
        return nil
    }

    let selectedCalendarIDs = settingsStore.selectedCalendarIDs()
    guard !selectedCalendarIDs.isEmpty else {
        return nil
    }

    let searchStart = startedAt.addingTimeInterval(-600)
    let searchEnd = startedAt.addingTimeInterval(300)

    return eventStore.events(
        from: searchStart,
        to: searchEnd,
        selectedCalendarIDs: selectedCalendarIDs
    )
    .filter { !$0.isAllDay }
    .filter { $0.startDate >= searchStart && $0.startDate <= searchEnd }
    .sorted {
        if $0.startDate != $1.startDate {
            return $0.startDate < $1.startDate
        }

        return $0.endDate < $1.endDate
    }
    .first
    .flatMap { event in
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return nil
        }

        return UpcomingCalendarEvent(
            title: title,
            startDate: event.startDate,
            endDate: event.endDate,
            attendees: event.attendees
        )
    }
}
```

- [ ] **Step 4: Update test doubles to satisfy the new protocol**

```swift
struct NoopCalendarIntegration: CalendarIntegration {
    func authorizationState() -> CalendarAuthorizationState { .denied }
    func requestAccess() async -> CalendarAuthorizationState { .denied }
    func availableCalendars() -> [CalendarDescriptor] { [] }
    func upcomingEventForToday() -> UpcomingCalendarEvent? { nil }
    func eventMatchingRecordingStart(at startedAt: Date) -> UpcomingCalendarEvent? { nil }
}

private final class StubCalendarIntegration: CalendarIntegration, @unchecked Sendable {
    private let matchingEventValue: UpcomingCalendarEvent?

    init(
        authorization: CalendarAuthorizationState = .authorized,
        requestAccessResult: CalendarAuthorizationState? = nil,
        calendars: [CalendarDescriptor] = [],
        upcomingEvent: UpcomingCalendarEvent? = nil,
        matchingEvent: UpcomingCalendarEvent? = nil
    ) {
        self.matchingEventValue = matchingEvent
        // keep existing stored properties unchanged
    }

    func eventMatchingRecordingStart(at startedAt: Date) -> UpcomingCalendarEvent? {
        matchingEventValue
    }
}
```

- [ ] **Step 5: Run the calendar tests to verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeCalendarIntegrationTests -only-testing:QuickMeetingTests/CalendarSettingsViewModelTests`
Expected: PASS with the new recording-start matching behavior covered.

- [ ] **Step 6: Commit the calendar matching slice**

```bash
git add QuickMeeting/Services/Calendar/CalendarIntegration.swift QuickMeeting/Services/Calendar/NativeCalendarIntegration.swift QuickMeetingTests/NativeCalendarIntegrationTests.swift QuickMeetingTests/CalendarSettingsViewModelTests.swift
git commit -m "feat: add calendar meeting matching"
```

### Task 2: Recording-Time Title Resolution

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing app view model tests**

```swift
@Test
func startRecordingUsesMatchingCalendarEventTitleWhenAvailable() async throws {
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
                attendees: []
            )
        ),
        dateProvider: { startedAt },
        meetingIDProvider: { meetingIDs.removeFirst() }
    )

    await viewModel.startRecording()

    let persistedMeeting = try #require(try harness.context.fetch(FetchDescriptor<Meeting>()).first)
    #expect(persistedMeeting.title == "Design Review")
}

@Test
func startRecordingFallsBackToTimestampWhenCalendarMatchIsUnavailable() async throws {
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
}
```

- [ ] **Step 2: Run the app view model tests to verify they fail**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`
Expected: FAIL because `AppViewModel.startRecording()` still uses the old injected title provider and has no timestamp formatter behavior.

- [ ] **Step 3: Implement minimal title resolution in the app layer**

```swift
private let meetingTitleFormatter: DateFormatter

init(
    meetingStore: MeetingStore,
    meetingFileStore: MeetingFileStore,
    recordingService: any RecordingService,
    transcriptionService: (any TranscriptionServicing)? = nil,
    transcriptionProgressCenter: TranscriptionProgressCenter? = nil,
    recordingPermissions: (any RecordingPermissions)? = nil,
    meetingTranscriptStore: (any MeetingTranscriptStoring)? = nil,
    calendarIntegration: (any CalendarIntegration)? = nil,
    dateProvider: @escaping () -> Date = Date.init,
    meetingIDProvider: @escaping () -> UUID = UUID.init,
    meetingTitleFormatter: DateFormatter = AppViewModel.makeMeetingTitleFormatter()
) {
    self.meetingTitleFormatter = meetingTitleFormatter
    // keep existing assignments unchanged
}

func startRecording() async {
    // keep existing guards and permission flow unchanged
    let startedAt = dateProvider()
    let resolvedTitle = resolvedMeetingTitle(for: startedAt)
    let meeting = try meetingStore.createMeeting(
        id: meetingID,
        title: resolvedTitle,
        startedAt: startedAt,
        folderURL: artifacts.meetingFolderURL,
        audioFileURL: artifacts.audioFileURL
    )
}

private func resolvedMeetingTitle(for startedAt: Date) -> String {
    if let matchedEvent = calendarIntegration.eventMatchingRecordingStart(at: startedAt) {
        return matchedEvent.title
    }

    return meetingTitleFormatter.string(from: startedAt)
}

private static func makeMeetingTitleFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter
}
```

- [ ] **Step 4: Wire the production app to the new default behavior**

```swift
let calendarIntegration = NativeCalendarIntegration(settingsStore: calendarSettingsStore)
_appViewModel = StateObject(
    wrappedValue: AppViewModel(
        meetingStore: meetingStore,
        meetingFileStore: meetingFileStore,
        recordingService: recordingService,
        transcriptionService: transcriptionService,
        transcriptionProgressCenter: transcriptionProgressCenter,
        meetingTranscriptStore: meetingTranscriptStore,
        calendarIntegration: calendarIntegration
    )
)
```

- [ ] **Step 5: Run the app view model tests to verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`
Expected: PASS with event-title and fallback timestamp coverage.

- [ ] **Step 6: Commit the recording title resolution slice**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: add meeting autonaming"
```

### Task 3: Full Verification

**Files:**
- Verify only: `QuickMeeting/Services/Calendar/CalendarIntegration.swift`
- Verify only: `QuickMeeting/Services/Calendar/NativeCalendarIntegration.swift`
- Verify only: `QuickMeeting/ViewModels/AppViewModel.swift`
- Verify only: `QuickMeetingTests/NativeCalendarIntegrationTests.swift`
- Verify only: `QuickMeetingTests/CalendarSettingsViewModelTests.swift`
- Verify only: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Run the focused regression suite**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeCalendarIntegrationTests -only-testing:QuickMeetingTests/CalendarSettingsViewModelTests -only-testing:QuickMeetingTests/AppViewModelTests`
Expected: PASS for all targeted calendar and recording-title tests.

- [ ] **Step 2: Run the broader app tests that cover meeting persistence**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination platform=macOS -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/NativeCalendarIntegrationTests`
Expected: PASS with no regression in meeting creation and calendar integration behavior.

- [ ] **Step 3: Inspect the diff before wrapping up**

Run: `git diff --stat`
Expected: only the planned calendar, app view model, and test files changed, plus this plan doc.
