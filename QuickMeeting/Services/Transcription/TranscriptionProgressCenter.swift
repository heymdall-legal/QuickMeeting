//
//  TranscriptionProgressCenter.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Combine
import Foundation

@MainActor
final class TranscriptionProgressCenter: ObservableObject {
    @Published private var progressByMeetingID: [UUID: Double] = [:]

    func startTracking(meetingID: UUID) {
        progressByMeetingID[meetingID] = 0
    }

    func updateProgress(_ progress: Double, for meetingID: UUID) {
        guard let currentProgress = progressByMeetingID[meetingID] else {
            return
        }

        let clampedProgress = min(max(progress, 0), 1)
        guard clampedProgress >= currentProgress else {
            return
        }

        progressByMeetingID[meetingID] = clampedProgress
    }

    func finishTracking(meetingID: UUID) {
        progressByMeetingID.removeValue(forKey: meetingID)
    }

    func progress(for meetingID: UUID) -> Double? {
        progressByMeetingID[meetingID]
    }
}
