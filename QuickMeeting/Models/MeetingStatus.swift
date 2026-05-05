//
//  MeetingStatus.swift
//  QuickMeeting
//
//  Created by heymdall on 04.05.2026.
//

import Foundation

enum MeetingStatus: String, Codable, CaseIterable, Sendable {
    case recording
    case recorded
    case transcribing
    case completed
    case failed
}
