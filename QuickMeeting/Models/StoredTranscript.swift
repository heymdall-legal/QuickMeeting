//
//  StoredTranscript.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation

nonisolated struct StoredTranscript: Codable, Equatable, Sendable {
    var speakers: [TranscriptSpeaker]
    var segments: [TranscriptSegment]

    var fullText: String {
        segments
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

nonisolated enum TranscriptionCTCMode: String, Codable, CaseIterable, Sendable {
    case off
    case auto
    case ctc110m
    case ctc06b

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .auto: return "Auto"
        case .ctc110m: return "CTC 110M"
        case .ctc06b: return "CTC 0.6B"
        }
    }
}

nonisolated struct TranscriptionPipelineOptions: Codable, Equatable, Sendable {
    var languageCode: String?
    var ctcMode: TranscriptionCTCMode
    var isLLMCorrectionEnabled: Bool
    var isRealtimeTranscriptionEnabled: Bool

    init(
        languageCode: String? = nil,
        ctcMode: TranscriptionCTCMode = .off,
        isLLMCorrectionEnabled: Bool = false,
        isRealtimeTranscriptionEnabled: Bool = false
    ) {
        self.languageCode = languageCode
        self.ctcMode = ctcMode
        self.isLLMCorrectionEnabled = isLLMCorrectionEnabled
        self.isRealtimeTranscriptionEnabled = isRealtimeTranscriptionEnabled
    }
}

nonisolated struct TranscriptionPipelineMetadata: Codable, Equatable, Sendable {
    var asrModel: String
    var languageCode: String?
    var requestedCTCMode: TranscriptionCTCMode
    var resolvedCTCMode: TranscriptionCTCMode?
    var glossaryTermCount: Int
    var isLLMCorrectionEnabled: Bool
    var llmCorrectionModel: String?
    var warnings: [String]
    var completedAt: Date?

    init(
        asrModel: String,
        languageCode: String? = nil,
        requestedCTCMode: TranscriptionCTCMode = .off,
        resolvedCTCMode: TranscriptionCTCMode? = nil,
        glossaryTermCount: Int = 0,
        isLLMCorrectionEnabled: Bool = false,
        llmCorrectionModel: String? = nil,
        warnings: [String] = [],
        completedAt: Date? = nil
    ) {
        self.asrModel = asrModel
        self.languageCode = languageCode
        self.requestedCTCMode = requestedCTCMode
        self.resolvedCTCMode = resolvedCTCMode
        self.glossaryTermCount = glossaryTermCount
        self.isLLMCorrectionEnabled = isLLMCorrectionEnabled
        self.llmCorrectionModel = llmCorrectionModel
        self.warnings = warnings
        self.completedAt = completedAt
    }
}

nonisolated struct TranscriptionGlossaryTerm: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var text: String
    var aliases: [String]
    var weight: Float?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        aliases: [String] = [],
        weight: Float? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.aliases = aliases
        self.weight = weight
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedAliases: [String] {
        aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
