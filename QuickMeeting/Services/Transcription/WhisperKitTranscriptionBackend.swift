//
//  WhisperKitTranscriptionBackend.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Foundation
import WhisperKit

struct WhisperKitTranscriptionBackend: WhisperTranscriptionBackend {
    let downloadBaseURL: URL

    init(
        fileManager: FileManager = .default,
        downloadBaseURL: URL? = nil
    ) {
        self.downloadBaseURL = downloadBaseURL ?? Self.defaultDownloadBaseURL(fileManager: fileManager)
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        let whisperKit = try await WhisperKit(
            model: request.model.argmaxModelID,
            downloadBase: downloadBaseURL,
            modelFolder: request.modelFolderURL.path,
            download: false
        )

        let results = try await whisperKit.transcribe(audioPath: request.audioFileURL.path)
        let text = results
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = results
            .flatMap(\.segments)
            .map { segment in
                TranscriptSegment(
                    text: segment.text,
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end)
                )
            }

        return TranscriptionResult(fullText: text, segments: segments)
    }

    private static func defaultDownloadBaseURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return applicationSupportURL
            .appendingPathComponent("QuickMeeting", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }
}
