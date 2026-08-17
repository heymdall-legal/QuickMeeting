import Foundation
import Testing
@testable import QuickMeeting

struct OnlineDraftPipelineTests {
    @Test
    func revisionsReplaceOneUtteranceAndFinalizeAtPunctuation() async throws {
        let asr = StubStreamingASRBackend(partials: ["Привет", "Привет."], final: "Привет.")
        let diarizer = StubStreamingDiarizationBackend(intervals: [
            SpeakerInterval(speakerID: "online-speaker-0", startTime: 0, endTime: 2)
        ])
        let pipeline = OnlineDraftPipeline(asrBackend: asr, diarizationBackend: diarizer)
        let collector = OnlineDraftEventCollector()
        let stream = AsyncStream<TimestampedAudioChunk> { continuation in
            continuation.yield(TimestampedAudioChunk(
                startTime: 10,
                sampleRate: 48_000,
                samples: [Float](repeating: 0.1, count: 48_000)
            ))
            continuation.yield(TimestampedAudioChunk(
                startTime: 11,
                sampleRate: 48_000,
                samples: [Float](repeating: 0.1, count: 48_000)
            ))
            continuation.finish()
        }

        let telemetry = try await pipeline.run(stream: stream) { event in
            await collector.append(event)
        }
        let events = await collector.events
        let final = try #require(events.last)

        #expect(events.count == 3)
        #expect(Set(events.map(\.utteranceID)).count == 1)
        #expect(events.map(\.revision) == [1, 2, 3])
        #expect(final.text == "Привет.")
        #expect(final.isFinalWithinDraft)
        #expect(final.onlineSpeakerClusterID == "online-speaker-0")
        #expect(telemetry.partialRevisionCount == 2)
        #expect(await asr.processedSampleCounts == [16_000, 16_000])
    }

    @Test
    func boundedChannelDropsOnlyDraftBuffersWhenConsumerFallsBehind() async {
        let channel = BoundedOnlineAudioChannel()
        let stream = channel.beginSession(capacity: 1)
        let chunk = TimestampedAudioChunk(startTime: 0, sampleRate: 16_000, samples: [0])

        #expect(channel.offer(chunk))
        #expect(channel.offer(chunk) == false)
        #expect(channel.metrics() == .init(acceptedBuffers: 1, droppedBuffers: 1))
        channel.finishSession()
        withExtendedLifetime(stream) {}
    }
}

private actor OnlineDraftEventCollector {
    private(set) var events: [OnlineDraftEvent] = []
    func append(_ event: OnlineDraftEvent) { events.append(event) }
}

private actor StubStreamingASRBackend: StreamingASRBackend {
    private var partials: [String]
    private let final: String
    private(set) var processedSampleCounts: [Int] = []

    init(partials: [String], final: String) {
        self.partials = partials
        self.final = final
    }

    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        progress(1, "ready")
    }
    func beginSession(languageCode: String) async throws {
        #expect(languageCode == "ru-RU")
    }
    func process(samples16k: [Float]) async throws -> String {
        processedSampleCounts.append(samples16k.count)
        return partials.isEmpty ? final : partials.removeFirst()
    }
    func finishSession() async throws -> String { final }
}

private actor StubStreamingDiarizationBackend: StreamingDiarizationBackend {
    private let intervals: [SpeakerInterval]
    init(intervals: [SpeakerInterval]) { self.intervals = intervals }
    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        progress(1, "ready")
    }
    func beginSession() async throws {}
    func process(samples16k: [Float]) async throws -> [SpeakerInterval] { intervals }
    func finishSession() async throws -> [SpeakerInterval] { intervals }
}
