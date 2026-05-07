//
//  MeetingStore.swift
//  QuickMeeting
//
//  Created by heymdall on 04.05.2026.
//

import Foundation
import SwiftData

enum MeetingStoreError: Error, Equatable {
    case audioFileOutsideRecordingFolder
    case meetingNotFound
}

struct MeetingStore {
    let modelContext: ModelContext

    @discardableResult
    func createMeeting(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        folderURL: URL,
        audioFileURL: URL
    ) throws -> Meeting {
        let now = Date()
        let recordingFolderURL = folderURL.standardizedFileURL
        let normalizedAudioFileURL = audioFileURL.standardizedFileURL

        guard MeetingStore.isFileURL(normalizedAudioFileURL, inside: recordingFolderURL) else {
            throw MeetingStoreError.audioFileOutsideRecordingFolder
        }

        let meeting = Meeting(
            id: id,
            title: title,
            startedAt: startedAt,
            status: .recording,
            audioFilePath: normalizedAudioFileURL.path(percentEncoded: false),
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(meeting)
        try modelContext.save()

        return meeting
    }

    private static func isFileURL(_ fileURL: URL, inside directoryURL: URL) -> Bool {
        let directoryComponents = directoryURL.pathComponents
        let fileComponents = fileURL.pathComponents

        guard fileComponents.count > directoryComponents.count else {
            return false
        }

        return Array(fileComponents.prefix(directoryComponents.count)) == directoryComponents
    }

    func deleteMeeting(_ meeting: Meeting) throws {
        modelContext.delete(meeting)
        try modelContext.save()
    }

    func fetchMeeting(id: UUID) throws -> Meeting {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { meeting in
                meeting.id == id
            }
        )

        guard let meeting = try modelContext.fetch(descriptor).first else {
            throw MeetingStoreError.meetingNotFound
        }

        return meeting
    }

    func finishRecording(meetingID: UUID, endedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.finishRecording(
            endedAt: endedAt,
            duration: endedAt.timeIntervalSince(meeting.startedAt),
            updatedAt: endedAt
        )
        try modelContext.save()
    }

    func startTranscription(meetingID: UUID, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.beginTranscription(updatedAt: updatedAt)
        try modelContext.save()
    }

    func completeTranscription(
        meetingID: UUID,
        transcriptFileURL: URL,
        transcriptPreview: String,
        updatedAt: Date
    ) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.completeTranscription(
            transcriptFilePath: transcriptFileURL.standardizedFileURL.path(),
            transcriptPreview: transcriptPreview,
            updatedAt: updatedAt
        )
        try modelContext.save()
    }

    func completeTranscription(
        meetingID: UUID,
        transcript: StoredTranscript,
        transcriptPreview: String,
        updatedAt: Date
    ) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.completeTranscription(
            transcript: transcript,
            transcriptPreview: transcriptPreview,
            updatedAt: updatedAt
        )
        try modelContext.save()
    }

    @discardableResult
    func renameSpeaker(
        meetingID: UUID,
        speakerID: String,
        displayName: String,
        updatedAt: Date
    ) throws -> StoredTranscript {
        let meeting = try fetchMeeting(id: meetingID)
        guard meeting.storedTranscript != nil else {
            throw MeetingTranscriptStoreError.sidecarMissing
        }

        guard let speaker = meeting.transcriptSpeakers.first(where: { $0.id == speakerID }) else {
            throw MeetingTranscriptStoreError.speakerNotFound
        }

        speaker.displayName = displayName
        meeting.setStatus(try meeting.status, updatedAt: updatedAt)
        try modelContext.save()

        guard let transcript = meeting.storedTranscript else {
            throw MeetingTranscriptStoreError.sidecarMissing
        }

        return transcript
    }

    func failTranscription(meetingID: UUID, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.failTranscription(updatedAt: updatedAt)
        try modelContext.save()
    }
}
