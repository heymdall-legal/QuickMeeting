//
//  TranscriptionService.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Foundation

enum TranscriptionServiceError: LocalizedError, Equatable {
    case meetingNotTranscribable
    case audioFileMissing
    case transcriptionAlreadyActive

    var errorDescription: String? {
        switch self {
        case .meetingNotTranscribable:
            return "This meeting can't be transcribed right now."
        case .audioFileMissing:
            return "Recording file is missing."
        case .transcriptionAlreadyActive:
            return "Another transcription is already in progress."
        }
    }
}

protocol TranscriptionServicing: AnyObject {
    func transcribe(meetingID: UUID) async throws
}

final class NoopTranscriptionService: TranscriptionServicing {
    func transcribe(meetingID _: UUID) async throws {}
}
