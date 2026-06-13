//
//  FluidTranscriptionService.swift
//  QuickMeeting
//
//  In-process transcription + diarization powered by FluidAudio. Designed as a
//  drop-in replacement for `SidecarTranscriptionService` that runs entirely on
//  device, without the bundled Python helper or a Hugging Face token.
//

import FluidAudio
import Foundation

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

enum FluidTranscriptionProgress: Sendable {
    case transcribing(Double)
    case diarizing(Double)
}

struct FluidTranscriptionResult: Sendable, Equatable {
    let speakers: [TranscriptSpeaker]
    let segments: [TranscriptSegment]
}

protocol FluidAudioTranscribing: Sendable {
    func transcribe(
        audioFileURL: URL,
        knownSpeakers: [FluidKnownSpeakerSnapshot],
        similarityThreshold: Float,
        progress: @escaping @Sendable (FluidTranscriptionProgress) -> Void
    ) async throws -> FluidTranscriptionResult
}

// MARK: - Service

@MainActor
final class FluidTranscriptionService: TranscriptionServicing {
    private let meetingStore: MeetingStore
    private let progressCenter: TranscriptionProgressCenter
    private let pipeline: any FluidAudioTranscribing
    private let knownSpeakerStore: KnownSpeakerStore?
    private let knownSpeakerEnrollmentService: (any KnownSpeakerEnrolling)?
    private let similarityThreshold: Float
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private var activeMeetingID: UUID?

    init(
        meetingStore: MeetingStore,
        progressCenter: TranscriptionProgressCenter,
        pipeline: (any FluidAudioTranscribing)? = nil,
        knownSpeakerStore: KnownSpeakerStore? = nil,
        knownSpeakerEnrollmentService: (any KnownSpeakerEnrolling)? = nil,
        similarityThreshold: Float = 0.8,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.meetingStore = meetingStore
        self.progressCenter = progressCenter
        self.pipeline = pipeline ?? DefaultFluidAudioPipeline()
        self.knownSpeakerStore = knownSpeakerStore
        self.knownSpeakerEnrollmentService = knownSpeakerEnrollmentService
        self.similarityThreshold = similarityThreshold
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
            let result = try await pipeline.transcribe(
                audioFileURL: audioFileURL,
                knownSpeakers: knownSpeakers,
                similarityThreshold: similarityThreshold
            ) { update in
                Task { @MainActor in
                    Self.applyProgress(update, meetingID: meetingID, progressCenter: progressCenter)
                }
            }

            let transcript = StoredTranscript(speakers: result.speakers, segments: result.segments)
            try meetingStore.completeTranscription(
                meetingID: meetingID,
                transcript: transcript,
                transcriptPreview: transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                updatedAt: dateProvider()
            )
            for speaker in transcript.speakers where speaker.labelSource == .bankMatched {
                do {
                    try await knownSpeakerEnrollmentService?.enroll(
                        displayName: speaker.displayName,
                        speaker: speaker,
                        meetingID: meetingID
                    )
                } catch {
                    // Keep the successful transcript even if centroid enrollment fails.
                }
            }
        } catch {
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
}

// MARK: - Default FluidAudio pipeline

/// Owns the FluidAudio managers and runs the transcription + diarization
/// pipeline off the main actor. Models are loaded lazily and reused between
/// runs to amortise the (substantial) load cost.
actor DefaultFluidAudioPipeline: FluidAudioTranscribing {
    private let asrVersion: AsrModelVersion
    private let diarizerConfig: OfflineDiarizerConfig

    private var asrManager: AsrManager?
    private var diarizer: OfflineDiarizerManager?

    init(
        asrVersion: AsrModelVersion = .v3,
        diarizerConfig: OfflineDiarizerConfig = DefaultFluidAudioPipeline.defaultDiarizerConfig
    ) {
        self.asrVersion = asrVersion
        self.diarizerConfig = diarizerConfig
    }

    nonisolated static let defaultDiarizerConfig = OfflineDiarizerConfig(
        clustering: OfflineDiarizerConfig.Clustering(
            threshold: 0.8,
            warmStartFa: 0.07,
            warmStartFb: 0.8,
            minSpeakers: nil,
            maxSpeakers: nil,
            numSpeakers: nil
        )
    )

    func transcribe(
        audioFileURL: URL,
        knownSpeakers: [FluidKnownSpeakerSnapshot],
        similarityThreshold: Float,
        progress: @escaping @Sendable (FluidTranscriptionProgress) -> Void
    ) async throws -> FluidTranscriptionResult {
        let samples = try AudioConverter().resampleAudioFile(path: audioFileURL.path)
        guard !samples.isEmpty else {
            throw FluidTranscriptionServiceError.noAudioDecoded
        }

        // 1) Transcription.
        let asrManager = try await loadASRManager()
        var decoderState = try TdtDecoderState()

        let progressStream = await asrManager.transcriptionProgressStream
        let transcriptionProgressTask = Task {
            for try await value in progressStream {
                progress(.transcribing(value))
            }
        }
        let transcriptionResult: ASRResult
        do {
            transcriptionResult = try await asrManager.transcribe(samples, decoderState: &decoderState)
        } catch {
            transcriptionProgressTask.cancel()
            throw error
        }
        transcriptionProgressTask.cancel()
        progress(.transcribing(1))

        // 2) Diarization (reuses the same samples).
        let diarizer = try await loadDiarizer()
        let diarizationResult = try await diarizer.process(audio: samples) { chunksProcessed, totalChunks in
            guard totalChunks > 0 else { return }
            progress(.diarizing(Double(chunksProcessed) / Double(totalChunks)))
        }
        progress(.diarizing(1))

        // Build the app's model types on the main actor, where they are
        // isolated (the project uses MainActor-by-default isolation). The
        // mapping itself is light, pure CPU work over the pipeline output.
        let segments = diarizationResult.segments
        let speakerDatabase = diarizationResult.speakerDatabase
        return await MainActor.run {
            Self.makeResult(
                transcriptionResult: transcriptionResult,
                segments: segments,
                speakerDatabase: speakerDatabase,
                knownSpeakers: knownSpeakers,
                similarityThreshold: similarityThreshold
            )
        }
    }

    private func loadASRManager() async throws -> AsrManager {
        if let asrManager {
            return asrManager
        }
        let models = try await AsrModels.downloadAndLoad(version: asrVersion)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asrManager = manager
        return manager
    }

    private func loadDiarizer() async throws -> OfflineDiarizerManager {
        if let diarizer {
            return diarizer
        }
        let manager = OfflineDiarizerManager(config: diarizerConfig)
        try await manager.prepareModels()
        diarizer = manager
        return manager
    }

    // MARK: Mapping

    @MainActor
    static func makeResult(
        transcriptionResult: ASRResult,
        segments: [TimedSpeakerSegment],
        speakerDatabase: [String: [Float]]?,
        knownSpeakers: [FluidKnownSpeakerSnapshot],
        similarityThreshold: Float
    ) -> FluidTranscriptionResult {
        let speakerEmbeddings = perSpeakerEmbeddings(segments: segments, speakerDatabase: speakerDatabase)

        // Diarized speaker IDs ordered by first appearance, mirroring how the
        // sidecar pipeline numbers "Speaker N" labels.
        let orderedSpeakerIDs = segments.reduce(into: [String]()) { result, segment in
            if !result.contains(segment.speakerId) {
                result.append(segment.speakerId)
            }
        }

        let transcriptSpeakers = orderedSpeakerIDs.enumerated().map { index, speakerID -> TranscriptSpeaker in
            let centroid = speakerEmbeddings[speakerID]
            let centroidValues = centroid?.map(Double.init)
            if let centroid,
               let match = bestMatch(
                   for: centroid,
                   in: knownSpeakers,
                   threshold: similarityThreshold
               ) {
                return TranscriptSpeaker(
                    id: speakerID,
                    displayName: match.displayName,
                    labelSource: .bankMatched,
                    matchedKnownSpeakerID: match.id,
                    centroid: centroidValues
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

        let transcriptSegments = makeSegments(
            transcriptionResult: transcriptionResult,
            diarizationSegments: segments
        )

        return FluidTranscriptionResult(speakers: transcriptSpeakers, segments: transcriptSegments)
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

    private nonisolated static func bestMatch(
        for centroid: [Float],
        in knownSpeakers: [FluidKnownSpeakerSnapshot],
        threshold: Float
    ) -> FluidKnownSpeakerSnapshot? {
        var bestSimilarity: Float = -1
        var bestSpeaker: FluidKnownSpeakerSnapshot?
        for speaker in knownSpeakers {
            for embedding in speaker.centroids {
                let similarity = cosineSimilarity(centroid, embedding)
                if similarity > bestSimilarity {
                    bestSimilarity = similarity
                    bestSpeaker = speaker
                }
            }
        }
        guard let bestSpeaker, bestSimilarity >= threshold else {
            return nil
        }
        return bestSpeaker
    }

    /// Aligns transcribed tokens to diarized speakers by timestamp. Subword
    /// tokens are grouped into words first so a split word is attributed to the
    /// speaker who started it, then consecutive same-speaker words are merged
    /// into a single segment.
    @MainActor
    private static func makeSegments(
        transcriptionResult: ASRResult,
        diarizationSegments: [TimedSpeakerSegment]
    ) -> [TranscriptSegment] {
        guard let tokens = transcriptionResult.tokenTimings, !tokens.isEmpty else {
            let text = transcriptionResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [TranscriptSegment(text: text)]
        }

        struct Word {
            var text: String
            var startTime: TimeInterval
            var endTime: TimeInterval
        }

        var words: [Word] = []
        for token in tokens {
            let isWordStart = token.token.hasPrefix(" ") || token.token.hasPrefix("\u{2581}") || words.isEmpty
            if isWordStart {
                words.append(Word(text: token.token, startTime: token.startTime, endTime: token.endTime))
            } else {
                words[words.count - 1].text += token.token
                words[words.count - 1].endTime = token.endTime
            }
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
        for word in words {
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
