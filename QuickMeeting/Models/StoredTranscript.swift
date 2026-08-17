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

    init(
        languageCode: String? = nil,
        ctcMode: TranscriptionCTCMode = .off,
        isLLMCorrectionEnabled: Bool = false
    ) {
        self.languageCode = languageCode
        self.ctcMode = ctcMode
        self.isLLMCorrectionEnabled = isLLMCorrectionEnabled
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
    var jobTelemetry: TranscriptionJobTelemetry?

    init(
        asrModel: String,
        languageCode: String? = nil,
        requestedCTCMode: TranscriptionCTCMode = .off,
        resolvedCTCMode: TranscriptionCTCMode? = nil,
        glossaryTermCount: Int = 0,
        isLLMCorrectionEnabled: Bool = false,
        llmCorrectionModel: String? = nil,
        warnings: [String] = [],
        completedAt: Date? = nil,
        jobTelemetry: TranscriptionJobTelemetry? = nil
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
        self.jobTelemetry = jobTelemetry
    }
}

/// Stable, backend-neutral measurements for one transcription job. This is
/// embedded in the existing pipeline metadata blob so older meetings require
/// no data-model migration and continue to decode with `jobTelemetry == nil`.
nonisolated struct TranscriptionJobTelemetry: Codable, Equatable, Sendable {
    var jobID: UUID
    var startedAt: Date
    var runKind: TranscriptionRunKind
    var decodeResamplingSeconds: TimeInterval
    var modelLoadingSeconds: TimeInterval
    var asrSeconds: TimeInterval
    var ctcSeconds: TimeInterval
    var diarizationSegmentationSeconds: TimeInterval
    var embeddingSeconds: TimeInterval
    var clusteringSeconds: TimeInterval
    var alignmentSeconds: TimeInterval
    var voiceBankMatchingSeconds: TimeInterval
    var llmSeconds: TimeInterval
    var persistenceSeconds: TimeInterval
    var totalSeconds: TimeInterval
    var peakMemoryBytes: UInt64
    var fluidAudioASRProcessingSeconds: TimeInterval?
    var fluidAudioDiarizationTimings: FluidAudioDiarizationTimings?

    init(
        jobID: UUID = UUID(),
        startedAt: Date = Date(),
        runKind: TranscriptionRunKind = .cold,
        decodeResamplingSeconds: TimeInterval = 0,
        modelLoadingSeconds: TimeInterval = 0,
        asrSeconds: TimeInterval = 0,
        ctcSeconds: TimeInterval = 0,
        diarizationSegmentationSeconds: TimeInterval = 0,
        embeddingSeconds: TimeInterval = 0,
        clusteringSeconds: TimeInterval = 0,
        alignmentSeconds: TimeInterval = 0,
        voiceBankMatchingSeconds: TimeInterval = 0,
        llmSeconds: TimeInterval = 0,
        persistenceSeconds: TimeInterval = 0,
        totalSeconds: TimeInterval = 0,
        peakMemoryBytes: UInt64 = 0,
        fluidAudioASRProcessingSeconds: TimeInterval? = nil,
        fluidAudioDiarizationTimings: FluidAudioDiarizationTimings? = nil
    ) {
        self.jobID = jobID
        self.startedAt = startedAt
        self.runKind = runKind
        self.decodeResamplingSeconds = decodeResamplingSeconds
        self.modelLoadingSeconds = modelLoadingSeconds
        self.asrSeconds = asrSeconds
        self.ctcSeconds = ctcSeconds
        self.diarizationSegmentationSeconds = diarizationSegmentationSeconds
        self.embeddingSeconds = embeddingSeconds
        self.clusteringSeconds = clusteringSeconds
        self.alignmentSeconds = alignmentSeconds
        self.voiceBankMatchingSeconds = voiceBankMatchingSeconds
        self.llmSeconds = llmSeconds
        self.persistenceSeconds = persistenceSeconds
        self.totalSeconds = totalSeconds
        self.peakMemoryBytes = peakMemoryBytes
        self.fluidAudioASRProcessingSeconds = fluidAudioASRProcessingSeconds
        self.fluidAudioDiarizationTimings = fluidAudioDiarizationTimings
    }
}

nonisolated enum TranscriptionRunKind: String, Codable, Equatable, Sendable {
    case cold
    case warm
}

/// Codable mirror of FluidAudio's `PipelineTimings`. Keeping the dependency
/// type out of persisted app models makes telemetry readable after an ASR or
/// diarization backend is replaced.
nonisolated struct FluidAudioDiarizationTimings: Codable, Equatable, Sendable {
    var modelCompilationSeconds: TimeInterval
    var audioLoadingSeconds: TimeInterval
    var segmentationSeconds: TimeInterval
    var embeddingExtractionSeconds: TimeInterval
    var speakerClusteringSeconds: TimeInterval
    var postProcessingSeconds: TimeInterval
    var totalInferenceSeconds: TimeInterval
    var totalProcessingSeconds: TimeInterval
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
