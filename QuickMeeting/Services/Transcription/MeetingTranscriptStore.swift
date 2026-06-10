//
//  MeetingTranscriptStore.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation

protocol MeetingTranscriptStoring: Sendable {
    func renameSpeaker(id: String, to displayName: String, in meetingID: UUID) throws -> StoredTranscript
}

enum MeetingTranscriptStoreError: LocalizedError, Equatable {
    case sidecarMissing
    case speakerNotFound

    var errorDescription: String? {
        switch self {
        case .sidecarMissing:
            return "Transcript data is unavailable."
        case .speakerNotFound:
            return "Speaker could not be updated."
        }
    }
}

struct MeetingTranscriptStore: MeetingTranscriptStoring {
    let meetingStore: MeetingStore?
    let dateProvider: () -> Date

    init(
        meetingStore: MeetingStore? = nil,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.meetingStore = meetingStore
        self.dateProvider = dateProvider
    }

    func loadTranscript(meetingID: UUID) throws -> StoredTranscript {
        guard let meetingStore else {
            throw MeetingTranscriptStoreError.sidecarMissing
        }

        let meeting = try meetingStore.fetchMeeting(id: meetingID)
        guard let transcript = meeting.storedTranscript else {
            throw MeetingTranscriptStoreError.sidecarMissing
        }

        return transcript
    }

    @discardableResult
    func renameSpeaker(id: String, to displayName: String, in meetingID: UUID) throws -> StoredTranscript {
        guard let meetingStore else {
            throw MeetingTranscriptStoreError.sidecarMissing
        }

        return try meetingStore.renameSpeaker(
            meetingID: meetingID,
            speakerID: id,
            displayName: displayName,
            updatedAt: dateProvider()
        )
    }
}
