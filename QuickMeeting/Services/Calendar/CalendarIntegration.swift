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
}
