//
//  UpcomingCalendarEvent.swift
//  QuickMeeting
//
//  Created by Codex on 08.05.2026.
//

import Foundation

struct UpcomingCalendarEvent: Equatable, Sendable {
    let id: String?
    let title: String
    let startDate: Date
    let endDate: Date
    let attendees: [UpcomingCalendarAttendee]

    init(
        id: String? = nil,
        title: String,
        startDate: Date,
        endDate: Date,
        attendees: [UpcomingCalendarAttendee]
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.attendees = attendees
    }
}

struct UpcomingCalendarAttendee: Equatable, Sendable {
    let displayName: String
    let emailAddress: String?
}
