//
//  MeetingStore.swift
//  QuickMeeting
//
//  Created by heymdall on 04.05.2026.
//

import Foundation
import SwiftData

enum MeetingStoreError: LocalizedError, Equatable {
    case audioFileOutsideRecordingFolder
    case meetingNotFound
    case invalidMeetingTitle

    var errorDescription: String? {
        switch self {
        case .audioFileOutsideRecordingFolder:
            return "Recording files must stay inside the meeting folder."
        case .meetingNotFound:
            return "Meeting could not be found."
        case .invalidMeetingTitle:
            return "Meeting title cannot be empty."
        }
    }
}

struct MeetingStore {
    let modelContext: ModelContext

    @discardableResult
    func createMeeting(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        attendeeNames: [String] = [],
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
            attendeeNames: attendeeNames,
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

    func renameMeeting(meetingID: UUID, title: String, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTitle.isEmpty else {
            throw MeetingStoreError.invalidMeetingTitle
        }

        meeting.renameTitle(to: normalizedTitle, updatedAt: updatedAt)
        try modelContext.save()
    }

    func startTranscription(meetingID: UUID, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.beginTranscription(updatedAt: updatedAt)
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

    func saveSummary(meetingID: UUID, summary: String, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.storeSummary(summary, updatedAt: updatedAt)
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
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        guard let speaker = meeting.transcriptSpeakers.first(where: { $0.id == speakerID }) else {
            throw MeetingTranscriptStoreError.speakerNotFound
        }

        speaker.displayName = displayName
        speaker.labelSourceRawValue = TranscriptSpeakerLabelSource.userAssigned.rawValue
        if speaker.matchedKnownSpeakerID != nil {
            speaker.matchedKnownSpeakerID = nil
        }
        meeting.setStatus(try meeting.status, updatedAt: updatedAt)
        try modelContext.save()

        guard let transcript = meeting.storedTranscript else {
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        return transcript
    }

    func failTranscription(meetingID: UUID, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.failTranscription(updatedAt: updatedAt)
        try modelContext.save()
    }

    func storeWaveform(meetingID: UUID, samples: [Double]) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.storeWaveform(samples, updatedAt: Date())
        try modelContext.save()
    }

    func resetStuckTranscribingMeetings(updatedAt: Date) throws {
        let allMeetings = try modelContext.fetch(FetchDescriptor<Meeting>())
        var didChange = false
        for meeting in allMeetings where (try? meeting.status) == .transcribing {
            meeting.failTranscription(updatedAt: updatedAt)
            didChange = true
        }
        if didChange {
            try modelContext.save()
        }
    }

    func resetStuckRecordingMeetings(updatedAt: Date) throws {
        let allMeetings = try modelContext.fetch(FetchDescriptor<Meeting>())
        var didChange = false
        for meeting in allMeetings where (try? meeting.status) == .recording {
            meeting.finishRecording(
                endedAt: updatedAt,
                duration: updatedAt.timeIntervalSince(meeting.startedAt),
                updatedAt: updatedAt
            )
            didChange = true
        }
        if didChange {
            try modelContext.save()
        }
    }
}
