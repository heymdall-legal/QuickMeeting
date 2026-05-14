//
//  MeetingPresenceDetector.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Foundation

struct MeetingPresenceDetector {
    private let requiredStableSampleCount: Int
    private var stableMatchCount = 0
    private var hasConfirmedMeeting = false

    init(requiredStableSampleCount: Int = 3) {
        self.requiredStableSampleCount = requiredStableSampleCount
    }

    mutating func evaluate(_ sample: MeetingAppActivitySample) -> MeetingAppPresence {
        guard sample.isMicrophoneActive else {
            stableMatchCount = 0
            hasConfirmedMeeting = false
            return .inactive
        }

        if hasConfirmedMeeting {
            return .activeMeeting
        }

        let qualifiesForStart = sample.isRunning
            && (sample.hasVisibleWindow || sample.hadRecentFocus)

        guard qualifiesForStart else {
            stableMatchCount = 0
            return .inactive
        }

        stableMatchCount += 1
        guard stableMatchCount >= requiredStableSampleCount else {
            return .candidateActive
        }

        hasConfirmedMeeting = true
        return .activeMeeting
    }
}
