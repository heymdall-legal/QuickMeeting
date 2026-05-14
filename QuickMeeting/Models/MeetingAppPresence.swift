//
//  MeetingAppPresence.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Foundation

struct MeetingAppActivitySample: Equatable, Sendable {
    let bundleIdentifier: String
    let isRunning: Bool
    let isFrontmost: Bool
    let hadRecentFocus: Bool
    let hasVisibleWindow: Bool
    let isMicrophoneActive: Bool
}

enum MeetingAppPresence: Equatable, Sendable {
    case inactive
    case candidateActive
    case activeMeeting
    case ending
}
