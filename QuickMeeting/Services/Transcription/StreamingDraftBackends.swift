import FluidAudio
import Foundation

nonisolated protocol StreamingASRBackend: Sendable {
    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws
    func beginSession(languageCode: String) async throws
    func process(samples16k: [Float]) async throws -> String
    func finishSession() async throws -> String
}

nonisolated protocol StreamingDiarizationBackend: Sendable {
    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws
    func beginSession() async throws
    func process(samples16k: [Float]) async throws -> [SpeakerInterval]
    func finishSession() async throws -> [SpeakerInterval]
}

actor FluidNemotronStreamingASRBackend: StreamingASRBackend {
    private var sharedModels: SharedNemotronMultilingualModels?
    private var manager: StreamingNemotronMultilingualAsrManager?

    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        if sharedModels != nil {
            progress(1, "Nemotron ready")
            return
        }
        progress(0, "Loading Nemotron ru-RU")
        sharedModels = try await StreamingNemotronMultilingualAsrManager.downloadAndPreloadShared(
            languageCode: "ru-RU",
            chunkMs: 2_240,
            progressHandler: { update in
                progress(update.fractionCompleted, "Loading Nemotron ru-RU")
            }
        )
        progress(1, "Nemotron ready")
    }

    func beginSession(languageCode: String) async throws {
        guard let sharedModels else {
            throw OnlineDraftPipelineError.modelsUnavailable
        }
        let manager = StreamingNemotronMultilingualAsrManager()
        try await manager.loadFromShared(sharedModels)
        await manager.setForcedPrefix(true)
        await manager.setLanguage(languageCode)
        self.manager = manager
    }

    func process(samples16k: [Float]) async throws -> String {
        guard let manager else { throw OnlineDraftPipelineError.sessionNotStarted }
        _ = try await manager.process(samples: samples16k)
        return await manager.getPartialTranscript()
    }

    func finishSession() async throws -> String {
        guard let manager else { throw OnlineDraftPipelineError.sessionNotStarted }
        defer { self.manager = nil }
        return try await manager.finishWithTokenTimings().text
    }
}

actor FluidSortformerStreamingDiarizationBackend: StreamingDiarizationBackend {
    // Nemotron emits text on a 2.24 s model window. The efficient Sortformer
    // variant advances more audio per inference at roughly the same output
    // cadence, avoiding needless compute pressure from the 1.04 s variant.
    private let configuration = SortformerConfig.efficientV2_1
    private var models: SortformerModels?
    private var diarizer: SortformerDiarizer?

    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        if models != nil {
            progress(1, "Sortformer ready")
            return
        }
        progress(0, "Loading Sortformer")
        models = try await SortformerModels.loadFromHuggingFace(
            config: configuration,
            progressHandler: { update in
                progress(update.fractionCompleted, "Loading Sortformer")
            }
        )
        progress(1, "Sortformer ready")
    }

    func beginSession() async throws {
        guard let models else { throw OnlineDraftPipelineError.modelsUnavailable }
        let diarizer = SortformerDiarizer(config: configuration)
        diarizer.initialize(models: models)
        self.diarizer = diarizer
    }

    func process(samples16k: [Float]) async throws -> [SpeakerInterval] {
        guard let diarizer else { throw OnlineDraftPipelineError.sessionNotStarted }
        _ = try diarizer.process(samples: samples16k, sourceSampleRate: 16_000)
        return intervals(from: diarizer.timeline)
    }

    func finishSession() async throws -> [SpeakerInterval] {
        guard let diarizer else { throw OnlineDraftPipelineError.sessionNotStarted }
        defer { self.diarizer = nil }
        _ = try diarizer.finalizeSession()
        return intervals(from: diarizer.timeline)
    }

    private func intervals(from timeline: DiarizerTimeline) -> [SpeakerInterval] {
        timeline.speakers
            .sorted { $0.key < $1.key }
            .flatMap { index, speaker in
                (speaker.finalizedSegments + speaker.tentativeSegments).map { segment in
                    SpeakerInterval(
                        speakerID: "online-speaker-\(index)",
                        startTime: TimeInterval(segment.startTime),
                        endTime: TimeInterval(segment.endTime)
                    )
                }
            }
    }
}
