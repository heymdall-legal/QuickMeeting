//
//  KnownSpeakerEnrollmentService.swift
//  QuickMeeting
//
//  Created by Codex on 11.06.2026.
//

import Foundation

protocol KnownSpeakerEnrolling: Sendable {
    func enroll(displayName: String, speaker: TranscriptSpeaker, meetingID: UUID) async throws
}

@MainActor
final class KnownSpeakerEnrollmentService: KnownSpeakerEnrolling {
    private let store: KnownSpeakerStore
    private let dateProvider: () -> Date

    init(store: KnownSpeakerStore, dateProvider: @escaping () -> Date = Date.init) {
        self.store = store
        self.dateProvider = dateProvider
    }

    func enroll(displayName: String, speaker: TranscriptSpeaker, meetingID: UUID) async throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let centroid = speaker.centroid else {
            return
        }

        let now = dateProvider()
        let knownSpeaker = try store.findOrCreateSpeaker(named: trimmed, now: now)
        try store.appendCentroid(
            centroid,
            to: knownSpeaker.id,
            sourceMeetingID: meetingID,
            sourceSpeakerID: speaker.id,
            now: now
        )
    }
}
