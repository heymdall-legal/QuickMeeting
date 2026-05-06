//
//  TranscriptionArtifactWriter.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Foundation

struct TranscriptionArtifacts: Equatable {
    let transcriptFileURL: URL
    let previewText: String
}

struct TranscriptionArtifactWriter {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writeArtifacts(
        for result: TranscriptionResult,
        in meetingFolderURL: URL
    ) throws -> TranscriptionArtifacts {
        let transcriptFileURL = meetingFolderURL.appendingPathComponent("transcript.txt")
        let transcriptText = result.fullText.trimmingCharacters(in: .whitespacesAndNewlines)

        try transcriptText.write(to: transcriptFileURL, atomically: true, encoding: .utf8)

        return TranscriptionArtifacts(
            transcriptFileURL: transcriptFileURL,
            previewText: makePreviewText(from: result)
        )
    }

    func makePreviewText(from result: TranscriptionResult) -> String {
        result.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
