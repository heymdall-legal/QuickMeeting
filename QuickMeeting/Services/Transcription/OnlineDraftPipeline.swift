import Foundation

nonisolated enum OnlineDraftPipelineError: LocalizedError, Equatable {
    case alreadyRunning
    case modelsUnavailable
    case sessionNotStarted
    case invalidSampleRate(Double)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: "An online draft session is already running."
        case .modelsUnavailable: "Online draft models are unavailable."
        case .sessionNotStarted: "The online draft session has not started."
        case .invalidSampleRate(let rate): "Unsupported online audio sample rate: \(rate)."
        }
    }
}

nonisolated struct OnlineDraftTelemetry: Codable, Equatable, Sendable {
    var acceptedBuffers: Int = 0
    var droppedBuffers: Int = 0
    var processedAudioSeconds: TimeInterval = 0
    var asrWallSeconds: TimeInterval = 0
    var diarizationWallSeconds: TimeInterval = 0
    var partialRevisionCount: Int = 0
    var firstPartialLatencySeconds: TimeInterval?
    var flushWallSeconds: TimeInterval = 0
    var failureStage: String?
}

actor OnlineDraftPipeline {
    typealias EventSink = @MainActor @Sendable (OnlineDraftEvent) async -> Void

    private let asrBackend: any StreamingASRBackend
    private let diarizationBackend: any StreamingDiarizationBackend
    private var isRunning = false

    init(
        asrBackend: any StreamingASRBackend,
        diarizationBackend: any StreamingDiarizationBackend
    ) {
        self.asrBackend = asrBackend
        self.diarizationBackend = diarizationBackend
    }

    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        async let asr: Void = asrBackend.prepare { value, phase in
            progress(value * 0.5, phase)
        }
        async let diarization: Void = diarizationBackend.prepare { value, phase in
            progress(0.5 + value * 0.5, phase)
        }
        _ = try await (asr, diarization)
    }

    func run(
        stream: AsyncStream<TimestampedAudioChunk>,
        eventSink: @escaping EventSink
    ) async throws -> OnlineDraftTelemetry {
        guard !isRunning else { throw OnlineDraftPipelineError.alreadyRunning }
        isRunning = true
        defer { isRunning = false }

        let sessionStart = ContinuousClock.now
        try await prepare(progress: { _, _ in })
        async let asrStart: Void = asrBackend.beginSession(languageCode: "ru-RU")
        async let diarizationStart: Void = diarizationBackend.beginSession()
        _ = try await (asrStart, diarizationStart)

        var telemetry = OnlineDraftTelemetry()
        var baseTime: TimeInterval?
        var currentIntervals: [SpeakerInterval] = []
        var committedText = ""
        var activeEventID = UUID()
        var activeStart: TimeInterval = 0
        var revision = 0

        for await chunk in stream {
            try Task.checkCancellation()
            let relativeStart = Self.relativeTime(chunk.startTime, baseTime: &baseTime)
            let relativeEnd = relativeStart + Double(chunk.samples.count) / chunk.sampleRate
            let samples16k = try Self.resampleTo16k(chunk.samples, sourceRate: chunk.sampleRate)

            let asrStartTime = ContinuousClock.now
            async let text = asrBackend.process(samples16k: samples16k)
            let diarStartTime = ContinuousClock.now
            async let intervals = diarizationBackend.process(samples16k: samples16k)
            let (fullText, latestIntervals) = try await (text, intervals)
            telemetry.asrWallSeconds += Self.seconds(from: asrStartTime)
            telemetry.diarizationWallSeconds += Self.seconds(from: diarStartTime)
            telemetry.processedAudioSeconds = max(telemetry.processedAudioSeconds, relativeEnd)
            currentIntervals = latestIntervals

            let activeText = Self.uncommittedSuffix(fullText: fullText, committedText: committedText)
            guard !activeText.isEmpty else { continue }
            revision += 1
            let event = OnlineDraftEvent(
                utteranceID: activeEventID,
                revision: revision,
                startTime: activeStart,
                endTime: relativeEnd,
                text: activeText,
                onlineSpeakerClusterID: Self.speakerID(
                    startTime: activeStart,
                    endTime: relativeEnd,
                    intervals: currentIntervals
                ),
                isFinalWithinDraft: false,
                source: .online
            )
            await eventSink(event)
            telemetry.partialRevisionCount += 1
            if telemetry.firstPartialLatencySeconds == nil {
                telemetry.firstPartialLatencySeconds = Self.seconds(from: sessionStart)
            }

            if Self.endsUtterance(activeText), relativeEnd - activeStart >= 0.6 {
                var finalEvent = event
                finalEvent.revision += 1
                finalEvent.isFinalWithinDraft = true
                await eventSink(finalEvent)
                committedText = fullText
                activeEventID = UUID()
                activeStart = relativeEnd
                revision = 0
            }
        }

        let flushStart = ContinuousClock.now
        async let finalText = asrBackend.finishSession()
        async let finalIntervals = diarizationBackend.finishSession()
        let (fullText, intervals) = try await (finalText, finalIntervals)
        let remainingText = Self.uncommittedSuffix(fullText: fullText, committedText: committedText)
        if !remainingText.isEmpty {
            revision += 1
            await eventSink(OnlineDraftEvent(
                utteranceID: activeEventID,
                revision: revision,
                startTime: activeStart,
                endTime: telemetry.processedAudioSeconds,
                text: remainingText,
                onlineSpeakerClusterID: Self.speakerID(
                    startTime: activeStart,
                    endTime: telemetry.processedAudioSeconds,
                    intervals: intervals
                ),
                isFinalWithinDraft: true,
                source: .online
            ))
        }
        telemetry.flushWallSeconds = Self.seconds(from: flushStart)
        return telemetry
    }

    private static func relativeTime(
        _ absoluteTime: TimeInterval,
        baseTime: inout TimeInterval?
    ) -> TimeInterval {
        if baseTime == nil { baseTime = absoluteTime }
        return max(0, absoluteTime - (baseTime ?? absoluteTime))
    }

    private static func resampleTo16k(
        _ samples: [Float],
        sourceRate: Double
    ) throws -> [Float] {
        guard sourceRate.isFinite, sourceRate > 0 else {
            throw OnlineDraftPipelineError.invalidSampleRate(sourceRate)
        }
        if abs(sourceRate - 16_000) < 1 { return samples }
        let outputCount = Int((Double(samples.count) * 16_000 / sourceRate).rounded(.down))
        guard outputCount > 0 else { return [] }
        return (0..<outputCount).map { index in
            let position = Double(index) * sourceRate / 16_000
            let lower = min(Int(position), samples.count - 1)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(position - Double(lower))
            return samples[lower] + (samples[upper] - samples[lower]) * fraction
        }
    }

    private static func uncommittedSuffix(fullText: String, committedText: String) -> String {
        let normalized = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !committedText.isEmpty, normalized.hasPrefix(committedText) else { return normalized }
        return String(normalized.dropFirst(committedText.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func endsUtterance(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".!?…".contains(last)
    }

    private static func speakerID(
        startTime: TimeInterval,
        endTime: TimeInterval,
        intervals: [SpeakerInterval]
    ) -> String? {
        SpeakerWordAligner.speakerID(
            for: TimedWord(text: "", startTime: startTime, endTime: endTime, confidence: nil),
            intervals: intervals,
            gapTolerance: 0.2
        )
    }

    private static func seconds(from instant: ContinuousClock.Instant) -> TimeInterval {
        let duration = instant.duration(to: .now)
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    }
}
