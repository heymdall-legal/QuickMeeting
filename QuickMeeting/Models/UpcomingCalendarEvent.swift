//
//  UpcomingCalendarEvent.swift
//  QuickMeeting
//
//  Created by Codex on 08.05.2026.
//

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
