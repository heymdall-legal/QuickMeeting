//
//  MeetingTranscriptStore.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation

protocol MeetingTranscriptStoring: Sendable {
    func renameSpeaker(id: String, to displayName: String, in meetingFolderURL: URL) throws -> StoredTranscript
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
    let fileManager: FileManager
    let artifactWriter: TranscriptionArtifactWriter
    let meetingStore: MeetingStore?
    let dateProvider: () -> Date
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        artifactWriter: TranscriptionArtifactWriter = TranscriptionArtifactWriter(),
        meetingStore: MeetingStore? = nil,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.artifactWriter = artifactWriter
        self.meetingStore = meetingStore
        self.dateProvider = dateProvider
    }

    func loadTranscript(in meetingFolderURL: URL) throws -> StoredTranscript {
        let sidecarURL = meetingFolderURL.appendingPathComponent("transcript.json")
        guard fileManager.fileExists(atPath: sidecarURL.path) else {
            throw MeetingTranscriptStoreError.sidecarMissing
        }

        let data = try Data(contentsOf: sidecarURL)
        return try decoder.decode(StoredTranscript.self, from: data)
    }

    @discardableResult
    func renameSpeaker(id: String, to displayName: String, in meetingFolderURL: URL) throws -> StoredTranscript {
        var transcript = try loadTranscript(in: meetingFolderURL)
        guard let speakerIndex = transcript.speakers.firstIndex(where: { $0.id == id }) else {
            throw MeetingTranscriptStoreError.speakerNotFound
        }

        transcript.speakers[speakerIndex].displayName = displayName
        _ = try artifactWriter.writeArtifacts(for: transcript, in: meetingFolderURL)
        return transcript
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
