//
//  CalendarIntegration.swift
//  QuickMeeting
//
//  Created by Codex on 08.05.2026.
//

import Foundation

enum CalendarAuthorizationState: Equatable, Sendable {
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
    func eventMatchingRecordingStart(at startedAt: Date) -> UpcomingCalendarEvent?
    func calendarEventsForRecording(startedAt: Date, endedAt: Date?) -> [UpcomingCalendarEvent]
}

struct NoopCalendarIntegration: CalendarIntegration {
    func authorizationState() -> CalendarAuthorizationState {
        .denied
    }

    func requestAccess() async -> CalendarAuthorizationState {
        .denied
    }

    func availableCalendars() -> [CalendarDescriptor] {
        []
    }

    func upcomingEventForToday() -> UpcomingCalendarEvent? {
        nil
    }

    func eventMatchingRecordingStart(at startedAt: Date) -> UpcomingCalendarEvent? {
        nil
    }

    func calendarEventsForRecording(startedAt _: Date, endedAt _: Date?) -> [UpcomingCalendarEvent] {
        []
    }
}
