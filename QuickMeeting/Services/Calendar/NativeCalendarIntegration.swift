//
//  NativeCalendarIntegration.swift
//  QuickMeeting
//
//  Created by Codex on 08.05.2026.
//

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
        guard authorizationState() == .authorized else {
            return []
        }

        return eventStore.availableCalendars()
    }

    func upcomingEventForToday() -> UpcomingCalendarEvent? {
        guard authorizationState() == .authorized else {
            return nil
        }

        let selectedCalendarIDs = settingsStore.selectedCalendarIDs()
        guard !selectedCalendarIDs.isEmpty else {
            return nil
        }

        let currentDate = now()
        let startOfDay = calendar.startOfDay(for: currentDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }

        return eventStore.events(
            from: startOfDay,
            to: endOfDay,
            selectedCalendarIDs: selectedCalendarIDs
        )
        .filter { !$0.isAllDay }
        .filter { $0.endDate > currentDate }
        .sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }

            return lhs.endDate < rhs.endDate
        }
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
        let fetchEnd = searchEnd.addingTimeInterval(1)

        return eventStore.events(
            from: searchStart,
            to: fetchEnd,
            selectedCalendarIDs: selectedCalendarIDs
        )
        .filter { !$0.isAllDay }
        .filter { $0.startDate >= searchStart && $0.startDate <= searchEnd }
        .sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }

            return lhs.endDate < rhs.endDate
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
}

private struct EventKitCalendarEventStore: CalendarEventStore {
    private let eventStore = EKEventStore()

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
        _ = try? await eventStore.requestFullAccessToEvents()
        return authorizationState()
    }

    func availableCalendars() -> [CalendarDescriptor] {
        eventStore.calendars(for: .event).map {
            CalendarDescriptor(id: $0.calendarIdentifier, title: $0.title)
        }
    }

    func events(
        from startDate: Date,
        to endDate: Date,
        selectedCalendarIDs: [String]
    ) -> [CalendarEvent] {
        let calendars = eventStore.calendars(for: .event).filter {
            selectedCalendarIDs.contains($0.calendarIdentifier)
        }
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )

        return eventStore.events(matching: predicate).map { event in
            CalendarEvent(
                title: event.title ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarID: event.calendar.calendarIdentifier,
                attendees: (event.attendees ?? []).map { attendee in
                    UpcomingCalendarAttendee(
                        displayName: attendee.name ?? "Unknown Attendee",
                        emailAddress: attendee.url.absoluteString
                    )
                }
            )
        }
    }
}
