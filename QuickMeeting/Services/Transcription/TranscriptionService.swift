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

@MainActor
protocol RealtimeTranscriptionCoordinating: AnyObject {
    func start(meeting: Meeting, options: TranscriptionPipelineOptions) async
    func stop(meetingID: UUID) async
    func cancel(meetingID: UUID)
}

@MainActor
final class NoopRealtimeTranscriptionCoordinator: RealtimeTranscriptionCoordinating {
    func start(meeting _: Meeting, options _: TranscriptionPipelineOptions) async {}
    func stop(meetingID _: UUID) async {}
    func cancel(meetingID _: UUID) {}
}
