//
//  FluidTranscriptionService.swift
//  QuickMeeting
//
//  In-process transcription + diarization powered by FluidAudio and running
//  entirely on device.
//

import FluidAudio
import Foundation
import OSLog

enum FluidTranscriptionServiceError: LocalizedError, Equatable {
    case noAudioDecoded
    case pipelineFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioDecoded:
            return "The recording could not be decoded for transcription."
        case .pipelineFailed(let reason):
            return reason
        }
    }
}

// MARK: - Pipeline abstraction (injectable for tests)

/// A Sendable snapshot of a known speaker's enrolled centroids, handed to the
/// pipeline so speaker matching can run off the main actor.
struct FluidKnownSpeakerSnapshot: Sendable, Equatable {
    let id: String
    let displayName: String
    let centroids: [[Float]]
}

private nonisolated struct VoiceBankMatchEvaluation: Sendable {
    let match: FluidKnownSpeakerSnapshot?
    let telemetry: VoiceBankMatchTelemetry
}

enum FluidTranscriptionProgress: Sendable {
    case transcribing(Double)
    case diarizing(Double)
}

struct FluidTranscriptionResult: Sendable, Equatable {
    let speakers: [TranscriptSpeaker]
    let segments: [TranscriptSegment]
    let rawTranscript: StoredTranscript?
    let metadata: TranscriptionPipelineMetadata

    init(
        speakers: [TranscriptSpeaker],
        segments: [TranscriptSegment],
        rawTranscript: StoredTranscript? = nil,
        metadata: TranscriptionPipelineMetadata = TranscriptionPipelineMetadata(asrModel: "Parakeet TDT v3")
    ) {
        self.speakers = speakers
        self.segments = segments
        self.rawTranscript = rawTranscript
        self.metadata = metadata
    }
}

protocol FluidAudioTranscribing: Sendable {
    func transcribe(
        audioFileURL: URL,
        knownSpeakers: [FluidKnownSpeakerSnapshot],
        voiceBankConfiguration: VoiceBankMatchingConfiguration,
        options: TranscriptionPipelineOptions,
        glossaryTerms: [TranscriptionGlossaryTerm],
        progress: @escaping @Sendable (FluidTranscriptionProgress) -> Void
    ) async throws -> FluidTranscriptionResult
}

// MARK: - Service

@MainActor
final class FluidTranscriptionService: TranscriptionServicing {
    private static let telemetryLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuickMeeting",
        category: "TranscriptionTelemetry"
    )
    private let meetingStore: MeetingStore
    private let progressCenter: TranscriptionProgressCenter
    private let pipeline: any FluidAudioTranscribing
    private let knownSpeakerStore: KnownSpeakerStore?
    private let languageStore: (any TranscriptionLanguageStoring)?
    private let glossaryStore: TranscriptionGlossaryStore?
    private let correctionService: (any TranscriptLLMCorrecting)?
    private let voiceBankConfigurationOverride: VoiceBankMatchingConfiguration?
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private var activeMeetingID: UUID?

    init(
        meetingStore: MeetingStore,
        progressCenter: TranscriptionProgressCenter,
        pipeline: (any FluidAudioTranscribing)? = nil,
        knownSpeakerStore: KnownSpeakerStore? = nil,
        languageStore: (any TranscriptionLanguageStoring)? = nil,
        glossaryStore: TranscriptionGlossaryStore? = nil,
        correctionService: (any TranscriptLLMCorrecting)? = nil,
        similarityThreshold: Float? = nil,
        ambiguityMargin: Float? = nil,
        minimumSpeakerSpeechDuration: TimeInterval? = nil,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.meetingStore = meetingStore
        self.progressCenter = progressCenter
        self.pipeline = pipeline ?? DefaultFluidAudioPipeline()
        self.knownSpeakerStore = knownSpeakerStore
        self.languageStore = languageStore
        self.glossaryStore = glossaryStore
        self.correctionService = correctionService
        if similarityThreshold != nil || ambiguityMargin != nil || minimumSpeakerSpeechDuration != nil {
            let defaults = VoiceBankMatchingConfiguration.default
            voiceBankConfigurationOverride = VoiceBankMatchingConfiguration(
                minimumScore: similarityThreshold ?? defaults.minimumScore,
                ambiguityMargin: ambiguityMargin ?? defaults.ambiguityMargin,
                minimumSpeechDurationSeconds: minimumSpeakerSpeechDuration
                    ?? defaults.minimumSpeechDurationSeconds
            )
        } else {
            voiceBankConfigurationOverride = nil
        }
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    func transcribe(meetingID: UUID) async throws {
        guard activeMeetingID == nil else {
            throw TranscriptionServiceError.transcriptionAlreadyActive
        }

        let meeting = try meetingStore.fetchMeeting(id: meetingID)
        let status = try meeting.status
        guard status == .recorded || status == .failed || status == .completed else {
            throw TranscriptionServiceError.meetingNotTranscribable
        }

        let audioFileURL = URL(fileURLWithPath: meeting.audioFilePath)
        guard fileManager.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionServiceError.audioFileMissing
        }

        let jobID = UUID()
        let jobStartedAt = dateProvider()
        let jobStartUptime = ProcessInfo.processInfo.systemUptime
        let memoryTracker = TranscriptionMemoryPeakTracker()
        var didStopMemoryTracking = false

        activeMeetingID = meetingID
        try meetingStore.startTranscription(meetingID: meetingID, updatedAt: dateProvider())
        progressCenter.startTracking(meetingID: meetingID)

        defer {
            progressCenter.finishTracking(meetingID: meetingID)
            activeMeetingID = nil
        }

        do {
            let knownSpeakers = try makeKnownSpeakerSnapshots()
            let progressCenter = progressCenter
            let options = languageStore?.pipelineOptions() ?? TranscriptionPipelineOptions()
            let voiceBankConfiguration = voiceBankConfigurationOverride ?? options.voiceBankMatching
            let glossaryTerms = glossaryStore?.enabledTerms() ?? []
            let result = try await pipeline.transcribe(
                audioFileURL: audioFileURL,
                knownSpeakers: knownSpeakers,
                voiceBankConfiguration: voiceBankConfiguration,
                options: options,
                glossaryTerms: glossaryTerms
            ) { update in
                Task { @MainActor in
                    Self.applyProgress(update, meetingID: meetingID, progressCenter: progressCenter)
                }
            }

            let pipelineTranscript = StoredTranscript(speakers: result.speakers, segments: result.segments)
            var visibleTranscript = pipelineTranscript
            var correctedTranscript: StoredTranscript?
            var metadata = result.metadata
            var telemetry = metadata.jobTelemetry ?? TranscriptionJobTelemetry()
            telemetry.jobID = jobID
            telemetry.startedAt = jobStartedAt
            metadata.languageCode = options.languageCode
            metadata.requestedCTCMode = options.ctcMode
            metadata.glossaryTermCount = glossaryTerms.count
            metadata.isLLMCorrectionEnabled = options.isLLMCorrectionEnabled
            metadata.completedAt = dateProvider()

            if options.isLLMCorrectionEnabled {
                let llmStart = ProcessInfo.processInfo.systemUptime
                defer {
                    telemetry.llmSeconds = ProcessInfo.processInfo.systemUptime - llmStart
                }
                if let correctionService {
                    do {
                        let correction = try await correctionService.correct(
                            transcript: pipelineTranscript,
                            glossaryTerms: glossaryTerms
                        )
                        visibleTranscript = correction.transcript
                        correctedTranscript = correction.transcript
                        metadata.llmCorrectionModel = correction.modelName
                        if correction.matchedSegmentCount == 0 {
                            metadata.warnings.append("LLM correction returned no matching segment ids.")
                        } else if correction.changedSegmentCount == 0 {
                            metadata.warnings.append("LLM correction returned no text changes.")
                        }
                    } catch {
                        metadata.warnings.append("LLM correction skipped: \(error.localizedDescription)")
                    }
                } else {
                    metadata.warnings.append("LLM correction skipped: correction service is unavailable.")
                }
            }

            let rawTranscript = result.rawTranscript ?? pipelineTranscript
            metadata.jobTelemetry = telemetry
            let persistenceStart = ProcessInfo.processInfo.systemUptime
            try meetingStore.completeTranscription(
                meetingID: meetingID,
                transcript: visibleTranscript,
                transcriptPreview: visibleTranscript.fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                rawTranscript: rawTranscript,
                correctedTranscript: correctedTranscript,
                pipelineMetadata: metadata,
                updatedAt: dateProvider()
            )
            telemetry.persistenceSeconds = ProcessInfo.processInfo.systemUptime - persistenceStart
            telemetry.totalSeconds = ProcessInfo.processInfo.systemUptime - jobStartUptime
            telemetry.peakMemoryBytes = memoryTracker.stop()
            didStopMemoryTracking = true
            metadata.jobTelemetry = telemetry
            try meetingStore.updateTranscriptionPipelineMetadata(
                meetingID: meetingID,
                metadata: metadata,
                updatedAt: dateProvider()
            )
            Self.logTelemetry(telemetry, meetingID: meetingID)
        } catch {
            if !didStopMemoryTracking {
                _ = memoryTracker.stop()
            }
            try? meetingStore.failTranscription(meetingID: meetingID, updatedAt: dateProvider())
            throw map(error)
        }
    }

    private func makeKnownSpeakerSnapshots() throws -> [FluidKnownSpeakerSnapshot] {
        guard let knownSpeakerStore else {
            return []
        }

        return try knownSpeakerStore.allSpeakers()
            .map { speaker in
                FluidKnownSpeakerSnapshot(
                    id: speaker.id,
                    displayName: speaker.displayName,
                    centroids: speaker.centroids
                        .sorted { $0.createdAt < $1.createdAt }
                        .map { $0.values.map(Float.init) }
                )
            }
            .filter { !$0.centroids.isEmpty }
    }

    private static func applyProgress(
        _ update: FluidTranscriptionProgress,
        meetingID: UUID,
        progressCenter: TranscriptionProgressCenter
    ) {
        switch update {
        case .transcribing(let value):
            progressCenter.updateProgress(value, for: meetingID)
        case .diarizing(let value):
            if progressCenter.diarizationProgress(for: meetingID) == nil {
                progressCenter.startDiarizationTracking(meetingID: meetingID, stepName: "Diarizing")
            }
            progressCenter.updateDiarizationProgress(value, stepName: "Diarizing", for: meetingID)
        }
    }

    private func map(_ error: Error) -> Error {
        if error is TranscriptionServiceError || error is FluidTranscriptionServiceError {
            return error
        }
        return FluidTranscriptionServiceError.pipelineFailed(error.localizedDescription)
    }

    private static func logTelemetry(_ telemetry: TranscriptionJobTelemetry, meetingID: UUID) {
        guard
            let data = try? JSONEncoder().encode(telemetry),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        telemetryLogger.info("meeting=\(meetingID.uuidString, privacy: .public) telemetry=\(json, privacy: .public)")
    }
}

// MARK: - Default FluidAudio pipeline

/// Owns the FluidAudio managers and runs the transcription + diarization
/// pipeline off the main actor. Models are loaded lazily and reused between
/// runs to amortise the (substantial) load cost.
actor DefaultFluidAudioPipeline: FluidAudioTranscribing {
    nonisolated private static let diarizationLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuickMeeting",
        category: "OfflineDiarization"
    )
    private let asrBackend: any ASRBackend
    private let diarizerConfigOverride: OfflineDiarizerConfig?

    private var diarizer: OfflineDiarizerManager?
    private var activeDiarizationConfiguration: OfflineDiarizationConfiguration?

    init(
        asrVersion: AsrModelVersion = .v3,
        asrBackend: (any ASRBackend)? = nil,
        diarizerConfig: OfflineDiarizerConfig? = nil
    ) {
        self.asrBackend = asrBackend ?? ParakeetASRBackend(version: asrVersion)
        diarizerConfigOverride = diarizerConfig
    }

    func transcribe(
        audioFileURL: URL,
        knownSpeakers: [FluidKnownSpeakerSnapshot],
        voiceBankConfiguration: VoiceBankMatchingConfiguration,
        options: TranscriptionPipelineOptions,
        glossaryTerms: [TranscriptionGlossaryTerm],
        progress: @escaping @Sendable (FluidTranscriptionProgress) -> Void
    ) async throws -> FluidTranscriptionResult {
        let needsDiarizerLoad = diarizer == nil
            || (diarizerConfigOverride == nil && activeDiarizationConfiguration != options.offlineDiarization)
        var telemetry = TranscriptionJobTelemetry(runKind: .warm)
        telemetry.offlineDiarizationConfiguration = options.offlineDiarization

        let decodeStart = ProcessInfo.processInfo.systemUptime
        let samples = try AudioConverter().resampleAudioFile(path: audioFileURL.path)
        telemetry.decodeResamplingSeconds = ProcessInfo.processInfo.systemUptime - decodeStart
        guard !samples.isEmpty else {
            throw FluidTranscriptionServiceError.noAudioDecoded
        }

        // 1) ASR. FluidAudio-specific result and CTC types stay inside the
        // Parakeet adapter; the pipeline receives only TimedTranscript.
        let asrOutput = try await asrBackend.transcribe(
            ASRBackendRequest(
                samples: samples,
                languageCode: options.languageCode,
                ctcMode: options.ctcMode,
                glossaryTerms: glossaryTerms
            )
        ) { value in
            progress(.transcribing(value))
        }
        telemetry.runKind = asrOutput.wasColdStart || needsDiarizerLoad ? .cold : .warm
        telemetry.modelLoadingSeconds = asrOutput.modelLoadingSeconds
        telemetry.asrSeconds = asrOutput.asrWallSeconds
        telemetry.ctcSeconds = asrOutput.ctcWallSeconds
        telemetry.fluidAudioASRProcessingSeconds = asrOutput.nativeProcessingSeconds

        // 2) Diarization (reuses the same samples).
        Self.logDiarizationConfiguration(options.offlineDiarization)
        let diarizerModelLoadStart = ProcessInfo.processInfo.systemUptime
        let diarizer = try await loadDiarizer(configuration: options.offlineDiarization)
        telemetry.modelLoadingSeconds += ProcessInfo.processInfo.systemUptime - diarizerModelLoadStart
        let diarizationResult = try await diarizer.process(audio: samples) { chunksProcessed, totalChunks in
            guard totalChunks > 0 else { return }
            progress(.diarizing(Double(chunksProcessed) / Double(totalChunks)))
        }
        progress(.diarizing(1))
        if let timings = diarizationResult.timings {
            telemetry.diarizationSegmentationSeconds = timings.segmentationSeconds
            telemetry.embeddingSeconds = timings.embeddingExtractionSeconds
            telemetry.clusteringSeconds = timings.speakerClusteringSeconds
            telemetry.fluidAudioDiarizationTimings = FluidAudioDiarizationTimings(
                modelCompilationSeconds: timings.modelCompilationSeconds,
                audioLoadingSeconds: timings.audioLoadingSeconds,
                segmentationSeconds: timings.segmentationSeconds,
                embeddingExtractionSeconds: timings.embeddingExtractionSeconds,
                speakerClusteringSeconds: timings.speakerClusteringSeconds,
                postProcessingSeconds: timings.postProcessingSeconds,
                totalInferenceSeconds: timings.totalInferenceSeconds,
                totalProcessingSeconds: timings.totalProcessingSeconds
            )
        }

        // Build the app's model types on the main actor, where they are
        // isolated (the project uses MainActor-by-default isolation). The
        // mapping itself is light, pure CPU work over the pipeline output.
        let segments = diarizationResult.segments
        let speakerDatabase = diarizationResult.speakerDatabase
        let finalCTCReplacements = asrOutput.replacements
        let finalCTCAdjustedText = asrOutput.adjustedText
        let finalResolvedCTCMode = asrOutput.resolvedCTCMode
        let finalWarnings = asrOutput.warnings
        let timedTranscript = asrOutput.transcript
        let asrModelName = asrOutput.modelName
        let pipelineTelemetry = telemetry

        return await MainActor.run {
            let mapping = Self.makeResultWithTimings(
                transcription: timedTranscript,
                segments: segments,
                speakerDatabase: speakerDatabase,
                knownSpeakers: knownSpeakers,
                voiceBankConfiguration: voiceBankConfiguration
            )
            let rawResult = mapping.result
            let rawTranscript = StoredTranscript(speakers: rawResult.speakers, segments: rawResult.segments)
            let adjustedSegments = Self.applyCTCReplacements(
                finalCTCReplacements,
                to: rawResult.segments
            )
            let finalSegments = finalCTCAdjustedText == nil ? rawResult.segments : adjustedSegments
            var completedTelemetry = pipelineTelemetry
            completedTelemetry.alignmentSeconds = mapping.alignmentSeconds
            completedTelemetry.voiceBankMatchingSeconds = mapping.voiceBankMatchingSeconds
            completedTelemetry.voiceBankMatches = mapping.voiceBankMatches
            return FluidTranscriptionResult(
                speakers: rawResult.speakers,
                segments: finalSegments,
                rawTranscript: rawTranscript,
                metadata: TranscriptionPipelineMetadata(
                    asrModel: asrModelName,
                    languageCode: options.languageCode,
                    requestedCTCMode: options.ctcMode,
                    resolvedCTCMode: finalResolvedCTCMode,
                    glossaryTermCount: glossaryTerms.count,
                    isLLMCorrectionEnabled: options.isLLMCorrectionEnabled,
                    warnings: finalWarnings,
                    jobTelemetry: completedTelemetry
                )
            )
        }
    }

    private func loadDiarizer(
        configuration: OfflineDiarizationConfiguration
    ) async throws -> OfflineDiarizerManager {
        if let diarizer,
           diarizerConfigOverride != nil || activeDiarizationConfiguration == configuration {
            return diarizer
        }
        let manager = OfflineDiarizerManager(
            config: diarizerConfigOverride ?? configuration.fluidAudioConfiguration
        )
        try await manager.prepareModels()
        diarizer = manager
        activeDiarizationConfiguration = configuration
        return manager
    }

    private nonisolated static func logDiarizationConfiguration(
        _ configuration: OfflineDiarizationConfiguration
    ) {
        diarizationLogger.info(
            "clusteringThreshold=\(configuration.clusteringThreshold, privacy: .public) stepRatio=\(configuration.segmentationStepRatio, privacy: .public) embeddingSkip=\(configuration.embeddingSkipStrategy.rawValue, privacy: .public)"
        )
    }

    // MARK: Mapping

    @MainActor
    static func makeResult(
        transcription: TimedTranscript,
        segments: [TimedSpeakerSegment],
        speakerDatabase: [String: [Float]]?,
        knownSpeakers: [FluidKnownSpeakerSnapshot],
        similarityThreshold: Float
    ) -> FluidTranscriptionResult {
        makeResultWithTimings(
            transcription: transcription,
            segments: segments,
            speakerDatabase: speakerDatabase,
            knownSpeakers: knownSpeakers,
            voiceBankConfiguration: VoiceBankMatchingConfiguration(
                minimumScore: similarityThreshold,
                ambiguityMargin: 0,
                minimumSpeechDurationSeconds: 0
            )
        ).result
    }

    @MainActor
    static func makeResult(
        transcription: TimedTranscript,
        segments: [TimedSpeakerSegment],
        speakerDatabase: [String: [Float]]?,
        knownSpeakers: [FluidKnownSpeakerSnapshot],
        voiceBankConfiguration: VoiceBankMatchingConfiguration
    ) -> FluidTranscriptionResult {
        makeResultWithTimings(
            transcription: transcription,
            segments: segments,
            speakerDatabase: speakerDatabase,
            knownSpeakers: knownSpeakers,
            voiceBankConfiguration: voiceBankConfiguration
        ).result
    }

    @MainActor
    private static func makeResultWithTimings(
        transcription: TimedTranscript,
        segments: [TimedSpeakerSegment],
        speakerDatabase: [String: [Float]]?,
        knownSpeakers: [FluidKnownSpeakerSnapshot],
        voiceBankConfiguration: VoiceBankMatchingConfiguration
    ) -> (
        result: FluidTranscriptionResult,
        alignmentSeconds: TimeInterval,
        voiceBankMatchingSeconds: TimeInterval,
        voiceBankMatches: [VoiceBankMatchTelemetry]
    ) {
        let voiceBankStart = ProcessInfo.processInfo.systemUptime
        let speakerEmbeddings = perSpeakerEmbeddings(segments: segments, speakerDatabase: speakerDatabase)

        // Diarized speaker IDs ordered by first appearance, mirroring how the
        // sidecar pipeline numbers "Speaker N" labels.
        let orderedSpeakerIDs = segments.reduce(into: [String]()) { result, segment in
            if !result.contains(segment.speakerId) {
                result.append(segment.speakerId)
            }
        }

        let speechDurationBySpeaker = segments.reduce(into: [String: TimeInterval]()) { durations, segment in
            durations[segment.speakerId, default: 0] += TimeInterval(segment.durationSeconds)
        }
        var matchTelemetry: [VoiceBankMatchTelemetry] = []
        let transcriptSpeakers = orderedSpeakerIDs.enumerated().map { index, speakerID -> TranscriptSpeaker in
            let centroid = speakerEmbeddings[speakerID]
            let centroidValues = centroid?.map(Double.init)
            if let centroid {
                let evaluation = evaluateMatch(
                    for: centroid,
                    diarizedSpeakerID: speakerID,
                    speechDuration: speechDurationBySpeaker[speakerID] ?? 0,
                    in: knownSpeakers,
                    configuration: voiceBankConfiguration
                )
                matchTelemetry.append(evaluation.telemetry)
                if let match = evaluation.match {
                    return TranscriptSpeaker(
                        id: speakerID,
                        displayName: match.displayName,
                        labelSource: .bankMatched,
                        matchedKnownSpeakerID: match.id,
                        centroid: centroidValues
                    )
                }
            } else {
                matchTelemetry.append(
                    VoiceBankMatchTelemetry(
                        diarizedSpeakerID: speakerID,
                        speechDurationSeconds: speechDurationBySpeaker[speakerID] ?? 0,
                        bestKnownSpeakerID: nil,
                        bestScore: nil,
                        secondBestKnownSpeakerID: nil,
                        secondBestScore: nil,
                        decision: .noCandidates
                    )
                )
            }
            return TranscriptSpeaker(
                id: speakerID,
                displayName: "Speaker \(index + 1)",
                labelSource: .generic,
                matchedKnownSpeakerID: nil,
                centroid: centroidValues
            )
        }
        let voiceBankMatchingSeconds = ProcessInfo.processInfo.systemUptime - voiceBankStart

        let alignmentStart = ProcessInfo.processInfo.systemUptime
        let transcriptSegments = makeSegments(
            transcription: transcription,
            diarizationSegments: segments
        )
        let alignmentSeconds = ProcessInfo.processInfo.systemUptime - alignmentStart

        return (
            FluidTranscriptionResult(speakers: transcriptSpeakers, segments: transcriptSegments),
            alignmentSeconds,
            voiceBankMatchingSeconds,
            matchTelemetry
        )
    }

    @MainActor
    private static func applyCTCReplacements(
        _ replacements: [ASRTextReplacement],
        to segments: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        guard !replacements.isEmpty else {
            return segments
        }

        return segments.map { segment in
            var text = segment.text
            for replacement in replacements where replacement.shouldReplace {
                text = replacePhrase(
                    replacement.originalText,
                    with: replacement.replacementText,
                    in: text
                )
            }
            return TranscriptSegment(
                id: segment.id,
                text: text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                speakerID: segment.speakerID
            )
        }
    }

    private nonisolated static func replacePhrase(
        _ phrase: String,
        with replacement: String,
        in text: String
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}])"# + escaped + #"(?![\p{L}\p{N}])"#
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    /// Prefer the pipeline-averaged `speakerDatabase` (only populated in debug
    /// mode) and otherwise average per-speaker embeddings from segments.
    private nonisolated static func perSpeakerEmbeddings(
        segments: [TimedSpeakerSegment],
        speakerDatabase: [String: [Float]]?
    ) -> [String: [Float]] {
        if let speakerDatabase, !speakerDatabase.isEmpty {
            return speakerDatabase
        }

        var sums: [String: [Float]] = [:]
        var counts: [String: Int] = [:]
        for segment in segments where !segment.embedding.isEmpty {
            if var existing = sums[segment.speakerId] {
                for index in 0..<min(existing.count, segment.embedding.count) {
                    existing[index] += segment.embedding[index]
                }
                sums[segment.speakerId] = existing
            } else {
                sums[segment.speakerId] = segment.embedding
            }
            counts[segment.speakerId, default: 0] += 1
        }

        var averaged: [String: [Float]] = [:]
        for (id, sum) in sums {
            let count = Float(counts[id] ?? 1)
            averaged[id] = sum.map { $0 / count }
        }
        return averaged
    }

    private nonisolated static func evaluateMatch(
        for centroid: [Float],
        diarizedSpeakerID: String,
        speechDuration: TimeInterval,
        in knownSpeakers: [FluidKnownSpeakerSnapshot],
        configuration: VoiceBankMatchingConfiguration
    ) -> VoiceBankMatchEvaluation {
        let ranked = knownSpeakers.compactMap { speaker -> (FluidKnownSpeakerSnapshot, Float)? in
            guard let score = speaker.centroids
                .map({ cosineSimilarity(centroid, $0) })
                .max()
            else {
                return nil
            }
            return (speaker, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.id < rhs.0.id
        }

        let best = ranked.first
        let second = ranked.dropFirst().first
        let decision: VoiceBankMatchDecision
        let match: FluidKnownSpeakerSnapshot?
        if best == nil {
            decision = .noCandidates
            match = nil
        } else if speechDuration < configuration.minimumSpeechDurationSeconds {
            decision = .insufficientSpeech
            match = nil
        } else if best!.1 < configuration.minimumScore {
            decision = .belowThreshold
            match = nil
        } else if let second, best!.1 - second.1 < configuration.ambiguityMargin {
            decision = .ambiguous
            match = nil
        } else {
            decision = .matched
            match = best!.0
        }

        return VoiceBankMatchEvaluation(
            match: match,
            telemetry: VoiceBankMatchTelemetry(
                diarizedSpeakerID: diarizedSpeakerID,
                speechDurationSeconds: speechDuration,
                bestKnownSpeakerID: best?.0.id,
                bestScore: best?.1,
                secondBestKnownSpeakerID: second?.0.id,
                secondBestScore: second?.1,
                decision: decision
            )
        )
    }

    /// Aligns backend-neutral timed words to diarized speakers by timestamp,
    /// then merges consecutive same-speaker words into transcript segments.
    @MainActor
    private static func makeSegments(
        transcription: TimedTranscript,
        diarizationSegments: [TimedSpeakerSegment]
    ) -> [TranscriptSegment] {
        guard !transcription.words.isEmpty else {
            let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [TranscriptSegment(text: text)]
        }

        func speaker(at time: TimeInterval) -> String? {
            diarizationSegments.first {
                Double($0.startTimeSeconds) <= time && time < Double($0.endTimeSeconds)
            }?.speakerId
        }

        struct Group {
            var speakerID: String?
            var text: String
            var startTime: TimeInterval
            var endTime: TimeInterval
        }

        var groups: [Group] = []
        var lastKnownSpeaker: String?
        for word in transcription.words {
            let resolved = speaker(at: word.startTime)
            let speakerID: String?
            if let resolved {
                speakerID = resolved
                lastKnownSpeaker = resolved
            } else {
                speakerID = lastKnownSpeaker
            }

            if !groups.isEmpty, groups[groups.count - 1].speakerID == speakerID {
                groups[groups.count - 1].text += word.text
                groups[groups.count - 1].endTime = word.endTime
            } else {
                groups.append(
                    Group(
                        speakerID: speakerID,
                        text: word.text,
                        startTime: word.startTime,
                        endTime: word.endTime
                    )
                )
            }
        }

        return groups.compactMap { group in
            let trimmed = group.text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return TranscriptSegment(
                text: trimmed,
                startTime: group.startTime,
                endTime: group.endTime,
                speakerID: group.speakerID
            )
        }
    }

    private nonisolated static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for index in 0..<a.count {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }
}

private extension OfflineDiarizationConfiguration {
    nonisolated var fluidAudioConfiguration: OfflineDiarizerConfig {
        let skipStrategy: OfflineDiarizerConfig.EmbeddingSkipStrategy
        switch embeddingSkipStrategy {
        case .none:
            skipStrategy = .none
        case .maskSimilarity095:
            skipStrategy = .maskSimilarity(threshold: 0.95)
        }
        return OfflineDiarizerConfig(
            clusteringThreshold: clusteringThreshold,
            segmentationStepRatio: segmentationStepRatio,
            embeddingSkipStrategy: skipStrategy
        )
    }
}
