//
//  WhisperTranscriptionBackend.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Foundation

struct TranscriptionRequest: Equatable, Sendable {
    let audioFileURL: URL
    let model: TranscriptionModel
    let modelFolderURL: URL
}

protocol WhisperTranscriptionBackend: Sendable {
func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}
