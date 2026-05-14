import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct CalendarSettingsViewModelTests {
    @Test
    func reloadAfterGrantSelectsAllCalendarsWhenNoSavedSelectionExists() async {
        let integration = StubCalendarIntegration(
            calendars: [
                CalendarDescriptor(id: "work", title: "Work"),
                CalendarDescriptor(id: "personal", title: "Personal")
            ]
        )
        let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: [])
        let viewModel = CalendarSettingsViewModel(
            calendarIntegration: integration,
            settingsStore: settingsStore
        )

        await viewModel.reload()

        #expect(viewModel.selectedCalendarIDs == ["work", "personal"])
        #expect(settingsStore.selectedCalendarIDs() == ["work", "personal"])
    }

    @Test
    func toggleCalendarSelectionPersistsChanges() {
        let integration = StubCalendarIntegration(
            calendars: [CalendarDescriptor(id: "work", title: "Work")]
        )
        let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: ["work"])
        let viewModel = CalendarSettingsViewModel(
            calendarIntegration: integration,
            settingsStore: settingsStore
        )

        viewModel.toggleCalendarSelection(id: "work")

        #expect(viewModel.selectedCalendarIDs == [])
        #expect(settingsStore.selectedCalendarIDs() == [])
    }

    @Test
    func selectAllCalendarsPersistsAvailableCalendarIDsInDisplayOrder() async {
        let integration = StubCalendarIntegration(
            calendars: [
                CalendarDescriptor(id: "personal", title: "Personal"),
                CalendarDescriptor(id: "work", title: "Work")
            ]
        )
        let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: ["work"])
        let viewModel = CalendarSettingsViewModel(
            calendarIntegration: integration,
            settingsStore: settingsStore
        )

        await viewModel.reload()
        viewModel.selectAllCalendars()

        #expect(viewModel.selectedCalendarIDs == ["personal", "work"])
        #expect(settingsStore.selectedCalendarIDs() == ["personal", "work"])
    }

    @Test
    func selectNoCalendarsClearsPersistedSelection() async {
        let integration = StubCalendarIntegration(
            calendars: [CalendarDescriptor(id: "work", title: "Work")]
        )
        let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: ["work"])
        let viewModel = CalendarSettingsViewModel(
            calendarIntegration: integration,
            settingsStore: settingsStore
        )

        await viewModel.reload()
        viewModel.selectNoCalendars()

        #expect(viewModel.selectedCalendarIDs == [])
        #expect(settingsStore.selectedCalendarIDs() == [])
    }

    @Test(arguments: [
        ([], "0 selected"),
        (["work"], "1 selected"),
        (["work", "personal"], "2 selected")
    ])
    func selectedCalendarSummaryTextReflectsSelectedCount(
        selectedIDs: [String],
        expectedText: String
    ) {
        let integration = StubCalendarIntegration()
        let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: selectedIDs)
        let viewModel = CalendarSettingsViewModel(
            calendarIntegration: integration,
            settingsStore: settingsStore
        )

        #expect(viewModel.selectedCalendarSummaryText == expectedText)
    }

    @Test
    func requestAccessReloadsCalendarsIntoSettingsState() async {
        let integration = StubCalendarIntegration(
            authorization: .notDetermined,
            requestAccessResult: .authorized,
            calendars: [CalendarDescriptor(id: "work", title: "Work")]
        )
        let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: [])
        let viewModel = CalendarSettingsViewModel(
            calendarIntegration: integration,
            settingsStore: settingsStore
        )

        #expect(viewModel.authorizationState == .notDetermined)

        await viewModel.requestAccess()

        #expect(viewModel.authorizationState == .authorized)
        #expect(viewModel.availableCalendars.map(\.title) == ["Work"])
    }
}

private final class InMemoryCalendarSelectionStore: CalendarSelectionStoring, @unchecked Sendable {
    private var storedIDs: [String]

    init(selectedCalendarIDs: [String]) {
        storedIDs = selectedCalendarIDs
    }

    func selectedCalendarIDs() -> [String] {
        storedIDs
    }

    func saveSelectedCalendarIDs(_ ids: [String]) {
        storedIDs = ids
    }
}

private final class StubCalendarIntegration: CalendarIntegration, @unchecked Sendable {
    private var currentAuthorization: CalendarAuthorizationState
    private let requestAccessResult: CalendarAuthorizationState?
    private let calendarsValue: [CalendarDescriptor]
    private let upcomingEventValue: UpcomingCalendarEvent?
    private let matchingEventValue: UpcomingCalendarEvent?

    init(
        authorization: CalendarAuthorizationState = .authorized,
        requestAccessResult: CalendarAuthorizationState? = nil,
        calendars: [CalendarDescriptor] = [],
        upcomingEvent: UpcomingCalendarEvent? = nil,
        matchingEvent: UpcomingCalendarEvent? = nil
    ) {
        currentAuthorization = authorization
        self.requestAccessResult = requestAccessResult
        calendarsValue = calendars
        upcomingEventValue = upcomingEvent
        matchingEventValue = matchingEvent
    }

    func authorizationState() -> CalendarAuthorizationState {
        currentAuthorization
    }

    func requestAccess() async -> CalendarAuthorizationState {
        if let requestAccessResult {
            currentAuthorization = requestAccessResult
        }

        return currentAuthorization
    }

    func availableCalendars() -> [CalendarDescriptor] {
        calendarsValue
    }

    func upcomingEventForToday() -> UpcomingCalendarEvent? {
        upcomingEventValue
    }

    func eventMatchingRecordingStart(at startedAt: Date) -> UpcomingCalendarEvent? {
        matchingEventValue
    }
}
