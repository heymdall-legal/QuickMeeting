//
//  MeetingTranscriptStore.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation

protocol MeetingTranscriptStoring: Sendable {
    func renameSpeaker(id: String, to displayName: String, in meetingFolderURL: URL) throws -> StoredTranscript
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
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        artifactWriter: TranscriptionArtifactWriter = TranscriptionArtifactWriter()
    ) {
        self.fileManager = fileManager
        self.artifactWriter = artifactWriter
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
}
