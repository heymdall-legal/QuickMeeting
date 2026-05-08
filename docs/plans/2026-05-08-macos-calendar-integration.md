**Goal:** Add a macOS Calendar integration that lets users choose calendars in Settings and shows the next upcoming timed event for today on the Home screen.

**Architecture:** Add a small calendar feature slice around EventKit: app-owned models and protocols, a native EventKit-backed integration service, a lightweight settings store for selected calendar IDs, and a dedicated settings view model and pane. `AppViewModel` stays the UI-facing boundary for Home and receives only app-owned calendar data, while Settings owns permission and calendar selection workflows.

**Tech Stack:** Swift, SwiftUI, EventKit, Foundation, Testing

---

## File Structure

**Create:**
- `QuickMeeting/Models/UpcomingCalendarEvent.swift`
- `QuickMeeting/Services/Calendar/CalendarIntegration.swift`
- `QuickMeeting/Services/Calendar/NativeCalendarIntegration.swift`
- `QuickMeeting/Services/Calendar/CalendarSettingsStore.swift`
- `QuickMeeting/ViewModels/CalendarSettingsViewModel.swift`
- `QuickMeeting/Views/Settings/CalendarSettingsView.swift`
- `QuickMeetingTests/CalendarSettingsStoreTests.swift`
- `QuickMeetingTests/CalendarSettingsViewModelTests.swift`
- `QuickMeetingTests/NativeCalendarIntegrationTests.swift`

**Modify:**
- `QuickMeeting/ViewModels/AppViewModel.swift`
- `QuickMeeting/Views/HomeView.swift`
- `QuickMeeting/Views/Settings/SettingsView.swift`
- `QuickMeeting/QuickMeetingApp.swift`
- `QuickMeetingTests/AppViewModelTests.swift`
- `docs/quickmeeting-architecture-design.md`
- `QuickMeetingTests/AppViewModelTests.swift`

**Test support to add inside existing/new test files:**
- `StubCalendarIntegration`
- `InMemoryCalendarSettingsStore`
- `FakeCalendarEventStore`
- small helper methods on `AppViewModelTestHarness` if needed for injecting the calendar dependency

**Why these files:**
- `UpcomingCalendarEvent.swift` keeps EventKit types out of the rest of the app and leaves space for attendee data later.
- `CalendarIntegration.swift`, `NativeCalendarIntegration.swift`, and `CalendarSettingsStore.swift` isolate permission, calendar lookup, event filtering, and settings persistence from UI code.
- `CalendarSettingsViewModel.swift` and `CalendarSettingsView.swift` fit the existing settings-pane pattern without bloating `SettingsView.swift`.
- `AppViewModel.swift`, `HomeView.swift`, `SettingsView.swift`, and `QuickMeetingApp.swift` are the integration points for wiring the new slice into the app shell.
- The tests cover the store, service rules, settings behavior, and Home-facing view-model behavior from the spec.

### Task 1: Add app-owned calendar models and filtering protocol

**Files:**
- Create: `QuickMeeting/Models/UpcomingCalendarEvent.swift`
- Create: `QuickMeeting/Services/Calendar/CalendarIntegration.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing Home-facing view-model test**

```swift
@Test
func loadUpcomingEventPublishesNextEventForHome() async {
    let harness = try AppViewModelTestHarness()
    let expected = UpcomingCalendarEvent(
        title: "Design Review",
        startDate: Date(timeIntervalSince1970: 1_800_000_000),
        endDate: Date(timeIntervalSince1970: 1_800_003_600),
        attendees: []
    )
    let calendar = StubCalendarIntegration(upcomingEvent: expected)
    let viewModel = AppViewModel(
        meetingStore: harness.meetingStore,
        meetingFileStore: harness.meetingFileStore,
        recordingService: harness.recordingService,
        transcriptionService: NoopTranscriptionService(),
        transcriptionProgressCenter: TranscriptionProgressCenter(),
        recordingPermissions: harness.recordingPermissions,
        calendarIntegration: calendar
    )

    await viewModel.loadUpcomingCalendarEvent()

    #expect(viewModel.upcomingCalendarEvent?.title == "Design Review")
}
```

- [ ] **Step 2: Run the targeted app-view-model test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: FAIL with missing `UpcomingCalendarEvent`, missing `calendarIntegration` dependency, or missing `loadUpcomingCalendarEvent()`.

- [ ] **Step 3: Add app-owned event and attendee models**

```swift
import Foundation

struct UpcomingCalendarEvent: Equatable, Sendable {
    let title: String
    let startDate: Date
    let endDate: Date
    let attendees: [UpcomingCalendarAttendee]
}

struct UpcomingCalendarAttendee: Equatable, Sendable {
    let displayName: String
    let emailAddress: String?
}
```

- [ ] **Step 4: Add the calendar integration protocol boundary**

```swift
import Foundation

enum CalendarAuthorizationState: Equatable {
    case notDetermined
    case denied
    case authorized
}

struct CalendarDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

protocol CalendarIntegration: Sendable {
    func authorizationState() -> CalendarAuthorizationState
    func requestAccess() async -> CalendarAuthorizationState
    func availableCalendars() -> [CalendarDescriptor]
    func upcomingEventForToday() -> UpcomingCalendarEvent?
}

struct NoopCalendarIntegration: CalendarIntegration {
    func authorizationState() -> CalendarAuthorizationState { .denied }
    func requestAccess() async -> CalendarAuthorizationState { .denied }
    func availableCalendars() -> [CalendarDescriptor] { [] }
    func upcomingEventForToday() -> UpcomingCalendarEvent? { nil }
}
```

- [ ] **Step 5: Extend `AppViewModel` with a Home-facing calendar surface**

```swift
@Published private(set) var upcomingCalendarEvent: UpcomingCalendarEvent?

private let calendarIntegration: any CalendarIntegration

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
    meetingTitleProvider: @escaping (Date) -> String = { _ in "Untitled Meeting" }
) {
    self.calendarIntegration = calendarIntegration ?? NoopCalendarIntegration()
    // existing assignments...
}

func loadUpcomingCalendarEvent() async {
    upcomingCalendarEvent = calendarIntegration.upcomingEventForToday()
}
```

- [ ] **Step 6: Re-run the targeted app-view-model test and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: PASS for the new upcoming-event publishing test.

- [ ] **Step 7: Commit the model and protocol boundary**

```bash
git add QuickMeeting/Models/UpcomingCalendarEvent.swift QuickMeeting/Services/Calendar/CalendarIntegration.swift QuickMeeting/ViewModels/AppViewModel.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: add calendar integration app models"
```

### Task 2: Add selected-calendar settings persistence

**Files:**
- Create: `QuickMeeting/Services/Calendar/CalendarSettingsStore.swift`
- Create: `QuickMeetingTests/CalendarSettingsStoreTests.swift`

- [ ] **Step 1: Write the failing settings-store test**

```swift
@Test
func selectedCalendarIdentifiersRoundTrip() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let store = CalendarSettingsStore(userDefaults: defaults)

    #expect(store.selectedCalendarIDs() == [])

    store.saveSelectedCalendarIDs(["work", "personal"])

    #expect(store.selectedCalendarIDs() == ["work", "personal"])
}
```

- [ ] **Step 2: Run the targeted store test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/CalendarSettingsStoreTests`

Expected: FAIL with missing `CalendarSettingsStore` or missing persistence methods.

- [ ] **Step 3: Add the lightweight settings store**

```swift
import Foundation

protocol CalendarSelectionStoring: Sendable {
    func selectedCalendarIDs() -> [String]
    func saveSelectedCalendarIDs(_ ids: [String])
}

struct CalendarSettingsStore: CalendarSelectionStoring {
    private let userDefaults: UserDefaults
    private let selectedCalendarIDsKey = "calendar.selectedIDs"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func selectedCalendarIDs() -> [String] {
        userDefaults.stringArray(forKey: selectedCalendarIDsKey) ?? []
    }

    func saveSelectedCalendarIDs(_ ids: [String]) {
        userDefaults.set(ids, forKey: selectedCalendarIDsKey)
    }
}
```

- [ ] **Step 4: Re-run the targeted store test and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/CalendarSettingsStoreTests`

Expected: PASS for the selected-calendar persistence test.

- [ ] **Step 5: Commit the settings store**

```bash
git add QuickMeeting/Services/Calendar/CalendarSettingsStore.swift QuickMeetingTests/CalendarSettingsStoreTests.swift
git commit -m "feat: persist selected calendars"
```

### Task 3: Implement native calendar integration filtering rules

**Files:**
- Create: `QuickMeeting/Services/Calendar/NativeCalendarIntegration.swift`
- Create: `QuickMeetingTests/NativeCalendarIntegrationTests.swift`

- [ ] **Step 1: Write the failing event-filtering test for in-progress and all-day behavior**

```swift
@Test
func upcomingEventForTodayExcludesAllDayAndEndedEvents() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = FakeCalendarEventStore(
        authorizationState: .authorized,
        calendars: [
            CalendarDescriptor(id: "work", title: "Work")
        ],
        events: [
            FakeCalendarEvent(
                title: "Offsite",
                startDate: now.addingTimeInterval(-7_200),
                endDate: now.addingTimeInterval(7_200),
                isAllDay: true,
                calendarID: "work"
            ),
            FakeCalendarEvent(
                title: "Finished",
                startDate: now.addingTimeInterval(-7_200),
                endDate: now.addingTimeInterval(-3_600),
                isAllDay: false,
                calendarID: "work"
            ),
            FakeCalendarEvent(
                title: "Standup",
                startDate: now.addingTimeInterval(-900),
                endDate: now.addingTimeInterval(900),
                isAllDay: false,
                calendarID: "work"
            ),
            FakeCalendarEvent(
                title: "Planning",
                startDate: now.addingTimeInterval(1_800),
                endDate: now.addingTimeInterval(3_600),
                isAllDay: false,
                calendarID: "work"
            )
        ]
    )
    let settings = InMemoryCalendarSettingsStore(selectedCalendarIDs: ["work"])
    let integration = NativeCalendarIntegration(
        eventStore: store,
        settingsStore: settings,
        now: { now },
        calendar: Calendar(identifier: .gregorian)
    )

    let event = integration.upcomingEventForToday()

    #expect(event?.title == "Standup")
}
```

- [ ] **Step 2: Run the targeted integration test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeCalendarIntegrationTests`

Expected: FAIL with missing `NativeCalendarIntegration` or missing event filtering behavior.

- [ ] **Step 3: Implement the EventKit-backed integration with filtering**

```swift
import Foundation

struct NativeCalendarIntegration: CalendarIntegration {
    private let eventStore: any CalendarEventStore
    private let settingsStore: any CalendarSelectionStoring
    private let now: () -> Date
    private let calendar: Calendar

    init(
        eventStore: any CalendarEventStore = EventKitCalendarEventStore(),
        settingsStore: any CalendarSelectionStoring,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.eventStore = eventStore
        self.settingsStore = settingsStore
        self.now = now
        self.calendar = calendar
    }

    func authorizationState() -> CalendarAuthorizationState {
        eventStore.authorizationState()
    }

    func requestAccess() async -> CalendarAuthorizationState {
        await eventStore.requestAccess()
    }

    func availableCalendars() -> [CalendarDescriptor] {
        guard authorizationState() == .authorized else { return [] }
        return eventStore.availableCalendars()
    }

    func upcomingEventForToday() -> UpcomingCalendarEvent? {
        guard authorizationState() == .authorized else { return nil }

        let selectedIDs = settingsStore.selectedCalendarIDs()
        guard !selectedIDs.isEmpty else { return nil }

        let now = now()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return eventStore.events(
            from: startOfDay,
            to: endOfDay,
            selectedCalendarIDs: selectedIDs
        )
            .filter { !$0.isAllDay }
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
            .map {
                UpcomingCalendarEvent(
                    title: $0.title.isEmpty ? "Untitled Event" : $0.title,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    attendees: $0.attendees
                )
            }
    }
}
```

- [ ] **Step 4: Add the event-store seam used by both EventKit and tests**

```swift
import EventKit
import Foundation

struct CalendarEvent: Sendable {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarID: String
    let attendees: [UpcomingCalendarAttendee]
}

protocol CalendarEventStore: Sendable {
    func authorizationState() -> CalendarAuthorizationState
    func requestAccess() async -> CalendarAuthorizationState
    func availableCalendars() -> [CalendarDescriptor]
    func events(from startDate: Date, to endDate: Date, selectedCalendarIDs: [String]) -> [CalendarEvent]
}

struct EventKitCalendarEventStore: CalendarEventStore {
    private let store = EKEventStore()

    func authorizationState() -> CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            return .authorized
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    func requestAccess() async -> CalendarAuthorizationState {
        _ = try? await store.requestFullAccessToEvents()
        return authorizationState()
    }

    func availableCalendars() -> [CalendarDescriptor] {
        store.calendars(for: .event)
            .map { CalendarDescriptor(id: $0.calendarIdentifier, title: $0.title) }
    }

    func events(from startDate: Date, to endDate: Date, selectedCalendarIDs: [String]) -> [CalendarEvent] {
        let calendars = store.calendars(for: .event)
            .filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        return store.events(matching: predicate).map {
            CalendarEvent(
                title: $0.title ?? "",
                startDate: $0.startDate,
                endDate: $0.endDate,
                isAllDay: $0.isAllDay,
                calendarID: $0.calendar.calendarIdentifier,
                attendees: ($0.attendees ?? []).map {
                    UpcomingCalendarAttendee(
                        displayName: $0.name ?? "Unknown Attendee",
                        emailAddress: $0.url?.absoluteString
                    )
                }
            )
        }
    }
}
```

- [ ] **Step 5: Add tests for no selection and no permission returning `nil`**

```swift
@Test
func upcomingEventForTodayReturnsNilWithoutPermission() {
    let store = FakeCalendarEventStore(authorizationState: .denied, calendars: [], events: [])
    let settings = InMemoryCalendarSettingsStore(selectedCalendarIDs: ["work"])
    let integration = NativeCalendarIntegration(eventStore: store, settingsStore: settings)

    #expect(integration.upcomingEventForToday() == nil)
}

@Test
func upcomingEventForTodayReturnsNilWithoutSelectedCalendars() {
    let store = FakeCalendarEventStore(authorizationState: .authorized, calendars: [CalendarDescriptor(id: "work", title: "Work")], events: [])
    let settings = InMemoryCalendarSettingsStore(selectedCalendarIDs: [])
    let integration = NativeCalendarIntegration(eventStore: store, settingsStore: settings)

    #expect(integration.upcomingEventForToday() == nil)
}
```

- [ ] **Step 6: Re-run the targeted integration test bundle and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeCalendarIntegrationTests`

Expected: PASS for filtering, permission, and empty-selection cases.

- [ ] **Step 7: Commit the native integration**

```bash
git add QuickMeeting/Services/Calendar/NativeCalendarIntegration.swift QuickMeetingTests/NativeCalendarIntegrationTests.swift
git commit -m "feat: add native calendar event lookup"
```

### Task 4: Add the calendar settings view model

**Files:**
- Create: `QuickMeeting/ViewModels/CalendarSettingsViewModel.swift`
- Create: `QuickMeetingTests/CalendarSettingsViewModelTests.swift`

- [ ] **Step 1: Write the failing first-grant default-selection test**

```swift
@Test
func reloadAfterGrantSelectsAllCalendarsWhenNoSavedSelectionExists() async {
    let integration = StubCalendarIntegration(
        authorizationState: .authorized,
        calendars: [
            CalendarDescriptor(id: "work", title: "Work"),
            CalendarDescriptor(id: "personal", title: "Personal")
        ]
    )
    let settings = InMemoryCalendarSettingsStore(selectedCalendarIDs: [])
    let viewModel = CalendarSettingsViewModel(
        calendarIntegration: integration,
        settingsStore: settings
    )

    await viewModel.reload()

    #expect(viewModel.selectedCalendarIDs == ["work", "personal"])
    #expect(settings.selectedCalendarIDs() == ["work", "personal"])
}
```

- [ ] **Step 2: Run the targeted settings-view-model test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/CalendarSettingsViewModelTests`

Expected: FAIL with missing `CalendarSettingsViewModel` or missing reload/default-selection behavior.

- [ ] **Step 3: Implement the settings view model**

```swift
import Foundation

@MainActor
final class CalendarSettingsViewModel: ObservableObject {
    @Published private(set) var authorizationState: CalendarAuthorizationState
    @Published private(set) var availableCalendars: [CalendarDescriptor] = []
    @Published var selectedCalendarIDs: [String] = []

    private let calendarIntegration: any CalendarIntegration
    private let settingsStore: any CalendarSelectionStoring

    init(
        calendarIntegration: any CalendarIntegration,
        settingsStore: any CalendarSelectionStoring
    ) {
        self.calendarIntegration = calendarIntegration
        self.settingsStore = settingsStore
        self.authorizationState = calendarIntegration.authorizationState()
        self.selectedCalendarIDs = settingsStore.selectedCalendarIDs()
    }

    func reload() async {
        authorizationState = calendarIntegration.authorizationState()
        guard authorizationState == .authorized else {
            availableCalendars = []
            selectedCalendarIDs = []
            return
        }

        availableCalendars = calendarIntegration.availableCalendars()
        if settingsStore.selectedCalendarIDs().isEmpty {
            selectedCalendarIDs = availableCalendars.map(\.id)
            settingsStore.saveSelectedCalendarIDs(selectedCalendarIDs)
        } else {
            selectedCalendarIDs = settingsStore.selectedCalendarIDs()
        }
    }

    func requestAccess() async {
        authorizationState = await calendarIntegration.requestAccess()
        await reload()
    }

    func toggleCalendarSelection(id: String) {
        if selectedCalendarIDs.contains(id) {
            selectedCalendarIDs.removeAll { $0 == id }
        } else {
            selectedCalendarIDs.append(id)
        }
        settingsStore.saveSelectedCalendarIDs(selectedCalendarIDs)
    }
}
```

- [ ] **Step 4: Add the toggle-persistence test**

```swift
@Test
func toggleCalendarSelectionPersistsChanges() {
    let integration = StubCalendarIntegration(
        authorizationState: .authorized,
        calendars: [CalendarDescriptor(id: "work", title: "Work")]
    )
    let settings = InMemoryCalendarSettingsStore(selectedCalendarIDs: ["work"])
    let viewModel = CalendarSettingsViewModel(
        calendarIntegration: integration,
        settingsStore: settings
    )

    viewModel.toggleCalendarSelection(id: "work")

    #expect(viewModel.selectedCalendarIDs == [])
    #expect(settings.selectedCalendarIDs() == [])
}
```

- [ ] **Step 5: Re-run the targeted settings-view-model test bundle and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/CalendarSettingsViewModelTests`

Expected: PASS for default-selection and toggle-persistence tests.

- [ ] **Step 6: Commit the settings view model**

```bash
git add QuickMeeting/ViewModels/CalendarSettingsViewModel.swift QuickMeetingTests/CalendarSettingsViewModelTests.swift
git commit -m "feat: add calendar settings view model"
```

### Task 5: Add the Settings calendar pane UI

**Files:**
- Create: `QuickMeeting/Views/Settings/CalendarSettingsView.swift`
- Modify: `QuickMeeting/Views/Settings/SettingsView.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`

- [ ] **Step 1: Write the failing settings-pane smoke test in the view model layer**

```swift
@Test
func requestAccessReloadsCalendarsIntoSettingsState() async {
    let integration = StubCalendarIntegration(
        authorizationState: .notDetermined,
        requestAccessResult: .authorized,
        calendars: [CalendarDescriptor(id: "work", title: "Work")]
    )
    let settings = InMemoryCalendarSettingsStore(selectedCalendarIDs: [])
    let viewModel = CalendarSettingsViewModel(
        calendarIntegration: integration,
        settingsStore: settings
    )

    await viewModel.requestAccess()

    #expect(viewModel.authorizationState == .authorized)
    #expect(viewModel.availableCalendars.map(\.title) == ["Work"])
}
```

- [ ] **Step 2: Run the targeted settings-view-model test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/CalendarSettingsViewModelTests`

Expected: FAIL until `requestAccess()` reloads granted calendars.

- [ ] **Step 3: Add the dedicated Settings pane view**

```swift
import SwiftUI

struct CalendarSettingsView: View {
    @ObservedObject var viewModel: CalendarSettingsViewModel

    var body: some View {
        Group {
            switch viewModel.authorizationState {
            case .authorized:
                List(viewModel.availableCalendars) { calendar in
                    Toggle(
                        isOn: Binding(
                            get: { viewModel.selectedCalendarIDs.contains(calendar.id) },
                            set: { _ in viewModel.toggleCalendarSelection(id: calendar.id) }
                        )
                    ) {
                        Text(calendar.title)
                    }
                }
            case .notDetermined, .denied:
                VStack(alignment: .leading, spacing: 12) {
                    Text("Allow QuickMeeting to access your calendars so Home can show your next event for today.")
                    Button("Grant Calendar Access") {
                        Task { await viewModel.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
            }
        }
        .navigationTitle("Calendar")
        .task {
            await viewModel.reload()
        }
    }
}
```

- [ ] **Step 4: Wire the pane into `SettingsView` and app construction**

```swift
struct SettingsView: View {
    @State private var selection: SettingsPane? = .models
    @ObservedObject var modelsViewModel: ModelsSettingsViewModel
    @ObservedObject var calendarViewModel: CalendarSettingsViewModel

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
        } detail: {
            switch selection ?? .models {
            case .models:
                ModelsSettingsView(viewModel: modelsViewModel)
            case .calendar:
                CalendarSettingsView(viewModel: calendarViewModel)
            }
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case models
    case calendar
}
```

```swift
@StateObject private var calendarSettingsViewModel: CalendarSettingsViewModel

let calendarSettingsStore = CalendarSettingsStore()
let calendarIntegration = NativeCalendarIntegration(settingsStore: calendarSettingsStore)

_calendarSettingsViewModel = StateObject(
    wrappedValue: CalendarSettingsViewModel(
        calendarIntegration: calendarIntegration,
        settingsStore: calendarSettingsStore
    )
)
```

- [ ] **Step 5: Re-run the targeted settings-view-model test bundle and verify it passes**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/CalendarSettingsViewModelTests`

Expected: PASS, including the request-access reload test.

- [ ] **Step 6: Commit the Settings pane wiring**

```bash
git add QuickMeeting/Views/Settings/CalendarSettingsView.swift QuickMeeting/Views/Settings/SettingsView.swift QuickMeeting/QuickMeetingApp.swift
git commit -m "feat: add calendar settings pane"
```

### Task 6: Show the next event on Home

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/Views/HomeView.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing no-event test**

```swift
@Test
func loadUpcomingEventClearsHomeStateWhenNoEventExists() async {
    let calendar = StubCalendarIntegration(upcomingEvent: nil)
    let harness = try AppViewModelTestHarness()
    let viewModel = AppViewModel(
        meetingStore: harness.meetingStore,
        meetingFileStore: harness.meetingFileStore,
        recordingService: harness.recordingService,
        transcriptionService: NoopTranscriptionService(),
        transcriptionProgressCenter: TranscriptionProgressCenter(),
        recordingPermissions: harness.recordingPermissions,
        calendarIntegration: calendar
    )

    await viewModel.loadUpcomingCalendarEvent()

    #expect(viewModel.upcomingCalendarEvent == nil)
}
```

- [ ] **Step 2: Run the targeted app-view-model test and verify it fails**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: FAIL until `loadUpcomingCalendarEvent()` consistently clears stale Home state.

- [ ] **Step 3: Update Home to render the event section only when data exists**

```swift
if let upcomingEvent = appViewModel.upcomingCalendarEvent {
    VStack(alignment: .leading, spacing: 6) {
        Text("Next Event Today")
            .font(.headline)

        Text(upcomingEvent.title)
            .font(.title3.weight(.semibold))

        Text("\(upcomingEvent.startDate.formatted(date: .omitted, time: .shortened)) - \(upcomingEvent.endDate.formatted(date: .omitted, time: .shortened))")
            .foregroundStyle(.secondary)
    }
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
}
```

- [ ] **Step 4: Trigger Home event loading from the view lifecycle**

```swift
.task {
    await appViewModel.loadUpcomingCalendarEvent()
}
```

- [ ] **Step 5: Re-run the targeted app-view-model tests and verify they pass**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: PASS for event-present and event-absent Home state tests.

- [ ] **Step 6: Commit the Home screen integration**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/Views/HomeView.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: show next calendar event on home"
```

### Task 7: Update architecture notes and run focused verification

**Files:**
- Modify: `docs/quickmeeting-architecture-design.md`

- [ ] **Step 1: Update the architecture document to reflect the shipped calendar slice**

```markdown
### Calendar Integration Service

- Requests calendar permission explicitly from Settings.
- Persists selected calendar identifiers outside meeting records.
- Exposes app-owned calendar descriptors and upcoming-event data to the UI.
- Filters today's events to timed entries whose `endDate` is still in the future.
```

- [ ] **Step 2: Run the full focused calendar-related test set**

Run: `xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-task3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/CalendarSettingsStoreTests -only-testing:QuickMeetingTests/CalendarSettingsViewModelTests -only-testing:QuickMeetingTests/NativeCalendarIntegrationTests -only-testing:QuickMeetingTests/AppViewModelTests`

Expected: PASS for all calendar store, view-model, integration, and Home-facing tests.

- [ ] **Step 3: Commit the docs and verification checkpoint**

```bash
git add docs/quickmeeting-architecture-design.md
git commit -m "docs: document calendar integration architecture"
```
