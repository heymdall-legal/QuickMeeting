//
//  TranscriptionModelCatalog.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Foundation

enum TranscriptionModelCatalog {
    static let supportedModels: [TranscriptionModel] = [
        TranscriptionModel(
            id: .tiny,
            displayName: "Tiny",
            argmaxModelID: "tiny",
            tokenizerRepositoryID: "openai/whisper-tiny",
            summary: "Fastest download and best for debugging or quick tests.",
            sortOrder: 0
        ),
        TranscriptionModel(
            id: .small,
            displayName: "Small",
            argmaxModelID: "small",
            tokenizerRepositoryID: "openai/whisper-small",
            summary: "Balanced speed and accuracy for everyday use.",
            sortOrder: 1
        ),
        TranscriptionModel(
            id: .largeV3,
            displayName: "Large v3",
            argmaxModelID: "large-v3-v20240930_626MB",
            tokenizerRepositoryID: "openai/whisper-large-v3",
            summary: "Highest accuracy, largest download, best for production-quality transcription.",
            sortOrder: 2
        ),
    ]

    static func model(for id: TranscriptionModelID) -> TranscriptionModel? {
        supportedModels.first { $0.id == id }
    }
}
