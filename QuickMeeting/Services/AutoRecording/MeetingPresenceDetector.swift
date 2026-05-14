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

    init(requiredStableSampleCount: Int = 3) {
        self.requiredStableSampleCount = requiredStableSampleCount
    }

    mutating func evaluate(_ sample: MeetingAppActivitySample) -> MeetingAppPresence {
        let qualifies = sample.isMicrophoneActive
            && sample.isRunning
            && (sample.hasVisibleWindow || sample.hadRecentFocus)

        guard qualifies else {
            stableMatchCount = 0
            return .inactive
        }

        stableMatchCount += 1
        return stableMatchCount >= requiredStableSampleCount ? .activeMeeting : .candidateActive
    }
}
