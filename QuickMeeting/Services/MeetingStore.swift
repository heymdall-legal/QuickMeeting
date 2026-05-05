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

    func finishRecording(meetingID: UUID, endedAt: Date) throws {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { meeting in
                meeting.id == meetingID
            }
        )

        guard let meeting = try modelContext.fetch(descriptor).first else {
            throw MeetingStoreError.meetingNotFound
        }

        meeting.finishRecording(
            endedAt: endedAt,
            duration: endedAt.timeIntervalSince(meeting.startedAt),
            updatedAt: endedAt
        )
        try modelContext.save()
    }
}
