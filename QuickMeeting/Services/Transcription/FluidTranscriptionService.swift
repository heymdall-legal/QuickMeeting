//
//  FluidTranscriptionService.swift
//  QuickMeeting
//
//  In-process transcription + diarization powered by FluidAudio and running
//  entirely on device.
//

import AVFAudio
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
        similarityThreshold: Float,
        options: TranscriptionPipelineOptions,
        glossaryTerms: [TranscriptionGlossaryTerm],
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
    private let languageStore: (any TranscriptionLanguageStoring)?
    private let glossaryStore: TranscriptionGlossaryStore?
    private let correctionService: (any TranscriptLLMCorrecting)?
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
        languageStore: (any TranscriptionLanguageStoring)? = nil,
        glossaryStore: TranscriptionGlossaryStore? = nil,
        correctionService: (any TranscriptLLMCorrecting)? = nil,
        similarityThreshold: Float = 0.8,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.meetingStore = meetingStore
        self.progressCenter = progressCenter
        self.pipeline = pipeline ?? DefaultFluidAudioPipeline()
        self.knownSpeakerStore = knownSpeakerStore
        self.knownSpeakerEnrollmentService = knownSpeakerEnrollmentService
        self.languageStore = languageStore
        self.glossaryStore = glossaryStore
        self.correctionService = correctionService
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
            let options = languageStore?.pipelineOptions() ?? TranscriptionPipelineOptions()
            let glossaryTerms = glossaryStore?.enabledTerms() ?? []
            let result = try await pipeline.transcribe(
                audioFileURL: audioFileURL,
                knownSpeakers: knownSpeakers,
                similarityThreshold: similarityThreshold,
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
            metadata.languageCode = options.languageCode
            metadata.requestedCTCMode = options.ctcMode
            metadata.glossaryTermCount = glossaryTerms.count
            metadata.isLLMCorrectionEnabled = options.isLLMCorrectionEnabled
            metadata.completedAt = dateProvider()

            if options.isLLMCorrectionEnabled {
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
            try meetingStore.completeTranscription(
                meetingID: meetingID,
                transcript: visibleTranscript,
                transcriptPreview: visibleTranscript.fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                rawTranscript: rawTranscript,
                correctedTranscript: correctedTranscript,
                pipelineMetadata: metadata,
                updatedAt: dateProvider()
            )
            for speaker in visibleTranscript.speakers where speaker.labelSource == .bankMatched {
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

// MARK: - Realtime transcription

@MainActor
final class RealtimeTranscriptionCoordinator: RealtimeTranscriptionCoordinating {
    private let meetingStore: MeetingStore
    private let dateProvider: () -> Date
    private let transcriberFactory: (
        TranscriptionPipelineOptions,
        @escaping @Sendable (String) -> Void
    ) -> any RealtimeTranscribing
    private var activeMeetingID: UUID?
    private var transcriber: (any RealtimeTranscribing)?

    init(
        meetingStore: MeetingStore,
        dateProvider: @escaping () -> Date = Date.init,
        transcriberFactory: @escaping (
            TranscriptionPipelineOptions,
            @escaping @Sendable (String) -> Void
        ) -> any RealtimeTranscribing = { options, partialHandler in
            RealtimeTranscriptionCoordinator.makeTranscriber(
                options: options,
                partialHandler: partialHandler
            )
        }
    ) {
        self.meetingStore = meetingStore
        self.dateProvider = dateProvider
        self.transcriberFactory = transcriberFactory
    }

    func start(meeting: Meeting, options: TranscriptionPipelineOptions) async {
        activeMeetingID = meeting.id
        let meetingID = meeting.id
        let coordinator = self
        let transcriber = transcriberFactory(options) { text in
            Task { @MainActor in
                coordinator.storeRealtimeTranscript(text, meetingID: meetingID)
            }
        }
        self.transcriber = transcriber

        Task {
            do {
                try await transcriber.start()
            } catch {
                await MainActor.run {
                    self.storeRealtimeUnavailableMessage(error, meetingID: meetingID)
                }
            }
        }
    }

    func append(_ buffer: RealtimeAudioBuffer) {
        guard let meetingID = activeMeetingID,
              let transcriber else {
            return
        }

        Task {
            do {
                try await transcriber.append(buffer)
            } catch {
                await MainActor.run {
                    guard self.activeMeetingID == meetingID else {
                        return
                    }

                    self.storeRealtimeUnavailableMessage(error, meetingID: meetingID)
                    self.transcriber = nil
                }
            }
        }
    }

    func stop(meetingID: UUID) async {
        guard activeMeetingID == meetingID else {
            return
        }

        if let finalText = try? await transcriber?.finish(),
           !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            storeRealtimeTranscript(finalText, meetingID: meetingID)
        }

        activeMeetingID = nil
        transcriber = nil
    }

    func cancel(meetingID: UUID) {
        guard activeMeetingID == meetingID else {
            return
        }

        activeMeetingID = nil
        transcriber = nil
    }

    private func storeRealtimeTranscript(_ text: String, meetingID: UUID) {
        try? meetingStore.storeRealtimeTranscript(
            meetingID: meetingID,
            text: text,
            updatedAt: dateProvider()
        )
    }

    private func storeRealtimeUnavailableMessage(_ error: Error, meetingID: UUID) {
        storeRealtimeTranscript(
            Self.realtimeUnavailableMessage(for: error),
            meetingID: meetingID
        )
    }

    nonisolated static func realtimeUnavailableMessage(for error: Error) -> String {
        let description = error.localizedDescription
        if description.contains("Hugging Face rate limit")
            || description.contains("Rate limited") {
            return """
            Realtime transcription unavailable: Fluid Audio models are not cached yet and Hugging Face rate-limited the download. Set HF_TOKEN or HUGGING_FACE_HUB_TOKEN, configure REGISTRY_URL, or retry later; after the models are cached, realtime transcription runs locally.
            """
        }

        return "Realtime transcription unavailable: \(description)"
    }

    nonisolated static func makeTranscriber(
        options: TranscriptionPipelineOptions,
        partialHandler: @escaping @Sendable (String) -> Void
    ) -> any RealtimeTranscribing {
        switch options.realtimeTranscriptionBackend {
        case .fluidAudio:
            return FluidRealtimeTranscriber(partialHandler: partialHandler)
        case .customOpenAICompatible:
            return CustomOpenAICompatibleRealtimeTranscriber(
                endpointURLString: options.realtimeTranscriptionEndpointURLString,
                modelName: options.realtimeTranscriptionModelName,
                languageCode: options.languageCode,
                partialHandler: partialHandler
            )
        }
    }
}

nonisolated protocol RealtimeTranscribing: Sendable {
    func start() async throws
    func append(_ buffer: RealtimeAudioBuffer) async throws
    func finish() async throws -> String
}

actor FluidRealtimeTranscriber: RealtimeTranscribing {
    private let manager: StreamingEouAsrManager
    private let partialHandler: @Sendable (String) -> Void
    private var didStart = false

    init(
        chunkSize: StreamingChunkSize = .ms320,
        partialHandler: @escaping @Sendable (String) -> Void
    ) {
        manager = StreamingEouAsrManager(chunkSize: chunkSize)
        self.partialHandler = partialHandler
    }

    func start() async throws {
        guard !didStart else {
            return
        }

        await manager.setPartialCallback { [partialHandler] transcript in
            partialHandler(transcript)
        }
        try await manager.loadModels()
        await manager.reset()
        didStart = true
    }

    func append(_ buffer: RealtimeAudioBuffer) async throws {
        try await start()
        guard let pcmBuffer = buffer.makePCMBuffer() else {
            return
        }

        _ = try await manager.process(audioBuffer: pcmBuffer)
    }

    func finish() async throws -> String {
        try await start()
        return try await manager.finish()
    }
}

nonisolated private enum RealtimeTranscriptionConfigurationError: LocalizedError {
    case invalidEndpointURL
    case emptyModelName

    var errorDescription: String? {
        switch self {
        case .invalidEndpointURL:
            "Realtime transcription endpoint URL is invalid."
        case .emptyModelName:
            "Realtime transcription model name is empty."
        }
    }
}

actor CustomOpenAICompatibleRealtimeTranscriber: RealtimeTranscribing {
    private let endpointURLString: String
    private let modelName: String
    private let languageCode: String?
    private let chunkDuration: TimeInterval
    private let partialHandler: @Sendable (String) -> Void
    private var pendingMonoSamples = [Float]()
    private var sampleRate: Double = 48_000
    private var accumulatedText = ""

    init(
        endpointURLString: String = TranscriptionPipelineOptions.defaultRealtimeTranscriptionEndpointURLString,
        modelName: String = TranscriptionPipelineOptions.defaultRealtimeTranscriptionModelName,
        languageCode: String? = nil,
        chunkDuration: TimeInterval = 5,
        partialHandler: @escaping @Sendable (String) -> Void
    ) {
        self.endpointURLString = endpointURLString
        self.modelName = modelName
        self.languageCode = languageCode
        self.chunkDuration = chunkDuration
        self.partialHandler = partialHandler
    }

    func start() async throws {
        _ = try validatedConfiguration()
    }

    func append(_ buffer: RealtimeAudioBuffer) async throws {
        guard buffer.frameCount > 0 else {
            return
        }

        sampleRate = buffer.sampleRate
        pendingMonoSamples.append(contentsOf: buffer.monoSamples())
        guard Double(pendingMonoSamples.count) / sampleRate >= chunkDuration else {
            return
        }

        try await flushPendingSamples()
    }

    func finish() async throws -> String {
        if !pendingMonoSamples.isEmpty {
            try await flushPendingSamples()
        }
        return accumulatedText
    }

    private func flushPendingSamples() async throws {
        let samples = pendingMonoSamples
        pendingMonoSamples.removeAll()
        let wavData = wavData(samples: samples, sampleRate: Int(sampleRate))
        let text = try await transcribe(wavData: wavData)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        accumulatedText = [accumulatedText, text]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        partialHandler(accumulatedText)
    }

    private func transcribe(wavData: Data) async throws -> String {
        let configuration = try validatedConfiguration()
        let boundary = "QuickMeetingRealtime-\(UUID().uuidString)"
        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            boundary: boundary,
            wavData: wavData,
            modelName: configuration.modelName
        )

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else {
            return ""
        }
        return text
    }

    private func multipartBody(boundary: String, wavData: Data, modelName: String) -> Data {
        var body = Data()
        appendField(name: "model", value: modelName, boundary: boundary, to: &body)
        if let languageCode = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !languageCode.isEmpty {
            appendField(name: "language", value: languageCode, boundary: boundary, to: &body)
        }
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"chunk.wav\"\r\n")
        body.appendString("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        body.appendString("\r\n--\(boundary)--\r\n")
        return body
    }

    private func validatedConfiguration() throws -> (endpointURL: URL, modelName: String) {
        let trimmedEndpoint = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpointURL = URL(string: trimmedEndpoint),
              endpointURL.scheme != nil,
              endpointURL.host != nil else {
            throw RealtimeTranscriptionConfigurationError.invalidEndpointURL
        }

        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelName.isEmpty else {
            throw RealtimeTranscriptionConfigurationError.emptyModelName
        }

        return (endpointURL, trimmedModelName)
    }

    private func appendField(name: String, value: String, boundary: String, to body: inout Data) {
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendString("\(value)\r\n")
    }

    private func wavData(samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        let bytesPerSample = 2
        let dataByteCount = samples.count * bytesPerSample
        data.appendString("RIFF")
        data.appendUInt32LE(UInt32(36 + dataByteCount))
        data.appendString("WAVE")
        data.appendString("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(1)
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(sampleRate * bytesPerSample))
        data.appendUInt16LE(UInt16(bytesPerSample))
        data.appendUInt16LE(16)
        data.appendString("data")
        data.appendUInt32LE(UInt32(dataByteCount))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            data.appendInt16LE(Int16(clamped * Float(Int16.max)))
        }
        return data
    }
}

private extension RealtimeAudioBuffer {
    nonisolated func monoSamples() -> [Float] {
        guard frameCount > 0 else {
            return []
        }

        guard channelCount > 1 else {
            return samplesByChannel.first ?? []
        }

        return (0..<frameCount).map { frameIndex in
            let sum = samplesByChannel.reduce(Float(0)) { partial, channel in
                guard frameIndex < channel.count else {
                    return partial
                }
                return partial + channel[frameIndex]
            }
            return sum / Float(channelCount)
        }
    }

    nonisolated func makePCMBuffer() -> AVAudioPCMBuffer? {
        guard frameCount > 0,
              channelCount > 0,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let destination = buffer.floatChannelData else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        for channelIndex in 0..<channelCount {
            let source = samplesByChannel[channelIndex]
            source.withUnsafeBufferPointer { pointer in
                if let baseAddress = pointer.baseAddress {
                    destination[channelIndex].update(from: baseAddress, count: min(source.count, frameCount))
                }
            }
        }

        return buffer
    }
}

private extension Data {
    nonisolated mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }

    nonisolated mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    nonisolated mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    nonisolated mutating func appendInt16LE(_ value: Int16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
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
        options: TranscriptionPipelineOptions,
        glossaryTerms: [TranscriptionGlossaryTerm],
        progress: @escaping @Sendable (FluidTranscriptionProgress) -> Void
    ) async throws -> FluidTranscriptionResult {
        let samples = try AudioConverter().resampleAudioFile(path: audioFileURL.path)
        guard !samples.isEmpty else {
            throw FluidTranscriptionServiceError.noAudioDecoded
        }

        // A nil code (or an unrecognised one) means auto-detect — no hint passed.
        let language = options.languageCode.flatMap(Language.init(rawValue:))

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
            transcriptionResult = try await asrManager.transcribe(samples, decoderState: &decoderState, language: language)
        } catch {
            transcriptionProgressTask.cancel()
            throw error
        }
        transcriptionProgressTask.cancel()
        progress(.transcribing(1))

        var ctcAdjustedText: String?
        var ctcReplacements: [VocabularyRescorer.RescoringResult] = []
        var warnings: [String] = []
        var resolvedCTCMode: TranscriptionCTCMode?
        if options.ctcMode != .off, !glossaryTerms.isEmpty {
            do {
                let ctcResult = try await applyCTCRescoring(
                    transcriptionResult: transcriptionResult,
                    samples: samples,
                    glossaryTerms: glossaryTerms,
                    mode: options.ctcMode
                )
                ctcAdjustedText = ctcResult.text
                ctcReplacements = ctcResult.replacements
                resolvedCTCMode = ctcResult.resolvedMode
            } catch {
                warnings.append("CTC vocabulary stage skipped: \(error.localizedDescription)")
            }
        }

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
        let finalCTCReplacements = ctcReplacements
        let finalCTCAdjustedText = ctcAdjustedText
        let finalResolvedCTCMode = resolvedCTCMode
        let finalWarnings = warnings

        return await MainActor.run {
            let rawResult = Self.makeResult(
                transcriptionResult: transcriptionResult,
                segments: segments,
                speakerDatabase: speakerDatabase,
                knownSpeakers: knownSpeakers,
                similarityThreshold: similarityThreshold
            )
            let rawTranscript = StoredTranscript(speakers: rawResult.speakers, segments: rawResult.segments)
            let adjustedSegments = Self.applyCTCReplacements(
                finalCTCReplacements,
                to: rawResult.segments
            )
            let finalSegments = finalCTCAdjustedText == nil ? rawResult.segments : adjustedSegments
            return FluidTranscriptionResult(
                speakers: rawResult.speakers,
                segments: finalSegments,
                rawTranscript: rawTranscript,
                metadata: TranscriptionPipelineMetadata(
                    asrModel: "Parakeet TDT v3",
                    languageCode: options.languageCode,
                    requestedCTCMode: options.ctcMode,
                    resolvedCTCMode: finalResolvedCTCMode,
                    glossaryTermCount: glossaryTerms.count,
                    isLLMCorrectionEnabled: options.isLLMCorrectionEnabled,
                    warnings: finalWarnings
                )
            )
        }
    }

    private func applyCTCRescoring(
        transcriptionResult: ASRResult,
        samples: [Float],
        glossaryTerms: [TranscriptionGlossaryTerm],
        mode: TranscriptionCTCMode
    ) async throws -> (
        text: String,
        replacements: [VocabularyRescorer.RescoringResult],
        resolvedMode: TranscriptionCTCMode
    ) {
        guard let tokenTimings = transcriptionResult.tokenTimings, !tokenTimings.isEmpty else {
            return (transcriptionResult.text, [], .off)
        }

        let resolvedMode: TranscriptionCTCMode = mode == .auto ? .ctc110m : mode
        let variant: CtcModelVariant = resolvedMode == .ctc06b ? .ctc06b : .ctc110m
        let models = try await CtcModels.downloadAndLoad(variant: variant)
        let tokenizer = try await CtcTokenizer.load(from: CtcModels.defaultCacheDirectory(for: variant))
        let tokenizedTerms = glossaryTerms.compactMap { term -> CustomVocabularyTerm? in
            let text = term.normalizedText
            guard !text.isEmpty else { return nil }
            let tokenIDs = tokenizer.encode(text)
            guard !tokenIDs.isEmpty else { return nil }
            return CustomVocabularyTerm(
                text: text,
                weight: term.weight,
                aliases: term.normalizedAliases.isEmpty ? nil : term.normalizedAliases,
                ctcTokenIds: tokenIDs
            )
        }
        guard !tokenizedTerms.isEmpty else {
            return (transcriptionResult.text, [], resolvedMode)
        }

        let vocabulary = CustomVocabularyContext(terms: tokenizedTerms)
        let spotter = CtcKeywordSpotter(models: models)
        let spotted = try await spotter.spotKeywordsWithLogProbs(
            audioSamples: samples,
            customVocabulary: vocabulary
        )
        let rescorer = try await VocabularyRescorer.create(
            spotter: spotter,
            vocabulary: vocabulary,
            ctcModelDirectory: CtcModels.defaultCacheDirectory(for: variant)
        )
        let output = rescorer.ctcTokenRescore(
            transcript: transcriptionResult.text,
            tokenTimings: tokenTimings,
            logProbs: spotted.logProbs,
            frameDuration: spotted.frameDuration
        )
        return (output.text, output.replacements, resolvedMode)
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

    @MainActor
    private static func applyCTCReplacements(
        _ replacements: [VocabularyRescorer.RescoringResult],
        to segments: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        guard !replacements.isEmpty else {
            return segments
        }

        return segments.map { segment in
            var text = segment.text
            for replacement in replacements where replacement.shouldReplace {
                guard let replacementWord = replacement.replacementWord else { continue }
                text = replacePhrase(
                    replacement.originalWord,
                    with: replacementWord,
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
