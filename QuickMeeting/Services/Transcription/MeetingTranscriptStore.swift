//
//  MeetingTranscriptStore.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation

protocol MeetingTranscriptStoring: Sendable {
    func renameSpeaker(id: String, to displayName: String, in meetingID: UUID) throws -> StoredTranscript
    func updateSegmentText(segmentID: UUID, text: String, in meetingID: UUID) throws -> StoredTranscript
    func splitSegment(segmentID: UUID, at cursorOffset: Int, in meetingID: UUID) throws -> TranscriptSegment
    func mergeSegmentWithPrevious(segmentID: UUID, in meetingID: UUID) throws -> TranscriptSegment
    func assignSegment(segmentID: UUID, toSpeakerNamed displayName: String, in meetingID: UUID) throws -> StoredTranscript
}

enum MeetingTranscriptStoreError: LocalizedError, Equatable {
    case transcriptMissing
    case speakerNotFound
    case segmentNotFound
    case invalidSegmentText
    case invalidSplitLocation
    case previousSegmentNotFound
    case invalidSpeakerName

    var errorDescription: String? {
        switch self {
        case .transcriptMissing:
            return "Transcript data is unavailable."
        case .speakerNotFound:
            return "Speaker could not be updated."
        case .segmentNotFound:
            return "Transcript segment could not be updated."
        case .invalidSegmentText:
            return "Transcript segment text cannot be empty."
        case .invalidSplitLocation:
            return "Transcript segment could not be split at that cursor position."
        case .previousSegmentNotFound:
            return "There is no previous transcript segment to merge with."
        case .invalidSpeakerName:
            return "Speaker name cannot be empty."
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
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        let meeting = try meetingStore.fetchMeeting(id: meetingID)
        guard let transcript = meeting.storedTranscript else {
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        return transcript
    }

    @discardableResult
    func renameSpeaker(id: String, to displayName: String, in meetingID: UUID) throws -> StoredTranscript {
        guard let meetingStore else {
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        return try meetingStore.renameSpeaker(
            meetingID: meetingID,
            speakerID: id,
            displayName: displayName,
            updatedAt: dateProvider()
        )
    }

    @discardableResult
    func updateSegmentText(segmentID: UUID, text: String, in meetingID: UUID) throws -> StoredTranscript {
        guard let meetingStore else {
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        return try meetingStore.updateTranscriptSegmentText(
            meetingID: meetingID,
            segmentID: segmentID,
            text: text,
            updatedAt: dateProvider()
        )
    }

    @discardableResult
    func splitSegment(segmentID: UUID, at cursorOffset: Int, in meetingID: UUID) throws -> TranscriptSegment {
        guard let meetingStore else {
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        return try meetingStore.splitTranscriptSegment(
            meetingID: meetingID,
            segmentID: segmentID,
            cursorOffset: cursorOffset,
            updatedAt: dateProvider()
        )
    }

    @discardableResult
    func mergeSegmentWithPrevious(segmentID: UUID, in meetingID: UUID) throws -> TranscriptSegment {
        guard let meetingStore else {
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        return try meetingStore.mergeTranscriptSegmentWithPrevious(
            meetingID: meetingID,
            segmentID: segmentID,
            updatedAt: dateProvider()
        )
    }

    @discardableResult
    func assignSegment(segmentID: UUID, toSpeakerNamed displayName: String, in meetingID: UUID) throws -> StoredTranscript {
        guard let meetingStore else {
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        return try meetingStore.assignTranscriptSegment(
            meetingID: meetingID,
            segmentID: segmentID,
            displayName: displayName,
            updatedAt: dateProvider()
        )
    }
}
