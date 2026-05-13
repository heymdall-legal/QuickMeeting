import Foundation
import Testing
@testable import QuickMeeting

struct NativeCalendarIntegrationTests {
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
                    organizer: nil,
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
                    organizer: nil,
                    attendees: []
                ),
                CalendarEvent(
                    title: "Earlier Match",
                    startDate: Date(timeIntervalSince1970: 35_850),
                    endDate: Date(timeIntervalSince1970: 36_300),
                    isAllDay: false,
                    calendarID: "work",
                    organizer: nil,
                    attendees: []
                ),
                CalendarEvent(
                    title: "Later Match",
                    startDate: Date(timeIntervalSince1970: 36_000),
                    endDate: Date(timeIntervalSince1970: 36_900),
                    isAllDay: false,
                    calendarID: "work",
                    organizer: nil,
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

    @Test
    func eventMatchingRecordingStartReturnsNilForEmptyMatchedTitle() {
        let eventStore = FakeCalendarEventStore(
            authorizationState: .authorized,
            calendars: [CalendarDescriptor(id: "work", title: "Work")],
            events: [
                CalendarEvent(
                    title: "   ",
                    startDate: Date(timeIntervalSince1970: 36_000),
                    endDate: Date(timeIntervalSince1970: 36_900),
                    isAllDay: false,
                    calendarID: "work",
                    organizer: nil,
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

        #expect(integration.eventMatchingRecordingStart(at: Date(timeIntervalSince1970: 35_900)) == nil)
    }

    @Test
    func upcomingEventForTodayExcludesAllDayAndEndedEvents() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let eventStore = FakeCalendarEventStore(
            authorizationState: .authorized,
            calendars: [CalendarDescriptor(id: "work", title: "Work")],
            events: [
                CalendarEvent(
                    title: "Offsite",
                    startDate: now.addingTimeInterval(-7_200),
                    endDate: now.addingTimeInterval(7_200),
                    isAllDay: true,
                    calendarID: "work",
                    organizer: nil,
                    attendees: []
                ),
                CalendarEvent(
                    title: "Finished",
                    startDate: now.addingTimeInterval(-7_200),
                    endDate: now.addingTimeInterval(-3_600),
                    isAllDay: false,
                    calendarID: "work",
                    organizer: nil,
                    attendees: []
                ),
                CalendarEvent(
                    title: "Standup",
                    startDate: now.addingTimeInterval(-900),
                    endDate: now.addingTimeInterval(900),
                    isAllDay: false,
                    calendarID: "work",
                    organizer: nil,
                    attendees: []
                ),
                CalendarEvent(
                    title: "Planning",
                    startDate: now.addingTimeInterval(1_800),
                    endDate: now.addingTimeInterval(3_600),
                    isAllDay: false,
                    calendarID: "work",
                    organizer: nil,
                    attendees: []
                )
            ]
        )
        let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: ["work"])
        let integration = NativeCalendarIntegration(
            eventStore: eventStore,
            settingsStore: settingsStore,
            now: { now },
            calendar: Calendar(identifier: .gregorian)
        )

        let event = integration.upcomingEventForToday()

        #expect(event?.title == "Standup")
    }

    @Test
    func upcomingEventForTodayReturnsNilWithoutPermission() {
        let eventStore = FakeCalendarEventStore(
            authorizationState: .denied,
            calendars: [],
            events: []
        )
        let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: ["work"])
        let integration = NativeCalendarIntegration(
            eventStore: eventStore,
            settingsStore: settingsStore
        )

        #expect(integration.upcomingEventForToday() == nil)
    }

    @Test
    func upcomingEventForTodayReturnsNilWithoutSelectedCalendars() {
        let eventStore = FakeCalendarEventStore(
            authorizationState: .authorized,
            calendars: [CalendarDescriptor(id: "work", title: "Work")],
            events: []
        )
        let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: [])
        let integration = NativeCalendarIntegration(
            eventStore: eventStore,
            settingsStore: settingsStore
        )

        #expect(integration.upcomingEventForToday() == nil)
    }

    @Test
    func eventMatchingRecordingStartAppendsOrganizerWhenMissingFromAttendees() {
        let startedAt = Date(timeIntervalSince1970: 36_000)
        let eventStore = FakeCalendarEventStore(
            authorizationState: .authorized,
            calendars: [CalendarDescriptor(id: "work", title: "Work")],
            events: [
                CalendarEvent(
                    title: "Design Review",
                    startDate: startedAt,
                    endDate: startedAt.addingTimeInterval(3_600),
                    isAllDay: false,
                    calendarID: "work",
                    organizer: UpcomingCalendarAttendee(
                        displayName: "Olga",
                        emailAddress: "olga@example.com"
                    ),
                    attendees: [
                        UpcomingCalendarAttendee(
                            displayName: "Masha",
                            emailAddress: "masha@example.com"
                        )
                    ]
                )
            ]
        )
        let settingsStore = InMemoryCalendarSelectionStore(selectedCalendarIDs: ["work"])
        let integration = NativeCalendarIntegration(
            eventStore: eventStore,
            settingsStore: settingsStore,
            calendar: Calendar(identifier: .gregorian)
        )

        let event = integration.eventMatchingRecordingStart(at: startedAt)

        #expect(event?.attendees.map(\.displayName) == ["Masha", "Olga"])
    }
}

private struct FakeCalendarEventStore: CalendarEventStore {
    let authorizationStateValue: CalendarAuthorizationState
    let calendarsValue: [CalendarDescriptor]
    let eventsValue: [CalendarEvent]

    init(
        authorizationState: CalendarAuthorizationState,
        calendars: [CalendarDescriptor],
        events: [CalendarEvent]
    ) {
        authorizationStateValue = authorizationState
        calendarsValue = calendars
        eventsValue = events
    }

    func authorizationState() -> CalendarAuthorizationState {
        authorizationStateValue
    }

    func requestAccess() async -> CalendarAuthorizationState {
        authorizationStateValue
    }

    func availableCalendars() -> [CalendarDescriptor] {
        calendarsValue
    }

    func events(from startDate: Date, to endDate: Date, selectedCalendarIDs: [String]) -> [CalendarEvent] {
        eventsValue.filter { event in
            selectedCalendarIDs.contains(event.calendarID)
                && event.startDate < endDate
                && event.endDate >= startDate
        }
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
