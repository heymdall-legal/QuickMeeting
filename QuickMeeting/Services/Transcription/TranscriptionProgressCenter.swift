//
//  TranscriptionProgressCenter.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Combine
import Foundation

struct DiarizationProgressState: Equatable, Sendable {
    let progress: Double
    let stepName: String?
}

@MainActor
final class TranscriptionProgressCenter: ObservableObject {
    @Published private var progressByMeetingID: [UUID: Double] = [:]
    @Published private var diarizationProgressByMeetingID: [UUID: DiarizationProgressState] = [:]

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
        diarizationProgressByMeetingID.removeValue(forKey: meetingID)
    }

    func progress(for meetingID: UUID) -> Double? {
        progressByMeetingID[meetingID]
    }

    func startDiarizationTracking(meetingID: UUID, stepName: String?) {
        diarizationProgressByMeetingID[meetingID] = DiarizationProgressState(
            progress: 0,
            stepName: normalizeStepName(stepName)
        )
    }

    func updateDiarizationProgress(_ progress: Double, stepName: String?, for meetingID: UUID) {
        let clamped = min(max(progress, 0), 1)
        let normalizedStepName = normalizeStepName(stepName)

        guard let current = diarizationProgressByMeetingID[meetingID] else {
            diarizationProgressByMeetingID[meetingID] = DiarizationProgressState(
                progress: clamped,
                stepName: normalizedStepName
            )
            return
        }

        if current.stepName != normalizedStepName {
            diarizationProgressByMeetingID[meetingID] = DiarizationProgressState(
                progress: clamped,
                stepName: normalizedStepName
            )
            return
        }

        guard clamped >= current.progress else { return }
        diarizationProgressByMeetingID[meetingID] = DiarizationProgressState(
            progress: clamped,
            stepName: normalizedStepName
        )
    }

    func diarizationProgress(for meetingID: UUID) -> DiarizationProgressState? {
        diarizationProgressByMeetingID[meetingID]
    }

    var isAnyTranscriptionActive: Bool {
        !progressByMeetingID.isEmpty
    }

    private func normalizeStepName(_ stepName: String?) -> String? {
        guard let stepName else {
            return nil
        }

        let trimmed = stepName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
