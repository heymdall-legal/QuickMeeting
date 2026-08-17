import AVFAudio
import Foundation
import Testing
@testable import QuickMeeting

struct OnlineDraftRealModelSmokeTests {
    @Test
    func cachedModelsProduceRussianDraftFromFixtureWhenRequested() async throws {
        let path = ProcessInfo.processInfo.environment["QM_REAL_ONLINE_AUDIO_PATH"]
            ?? "/private/tmp/quickmeeting-online-smoke.aiff"
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }

        let fixture = try Self.loadMonoAudio(at: URL(fileURLWithPath: path))
        let pipeline = OnlineDraftPipeline(
            asrBackend: FluidNemotronStreamingASRBackend(),
            diarizationBackend: FluidSortformerStreamingDiarizationBackend()
        )
        try await pipeline.prepare { _, _ in }
        let collector = RealModelDraftCollector()
        let samplesPerOffer = max(1, Int(fixture.sampleRate / 4))
        let stream = AsyncStream<TimestampedAudioChunk> { continuation in
            var offset = 0
            while offset < fixture.samples.count {
                let end = min(offset + samplesPerOffer, fixture.samples.count)
                continuation.yield(TimestampedAudioChunk(
                    startTime: Double(offset) / fixture.sampleRate,
                    sampleRate: fixture.sampleRate,
                    samples: Array(fixture.samples[offset..<end])
                ))
                offset = end
            }
            continuation.finish()
        }

        let telemetry = try await pipeline.run(stream: stream) { event in
            await collector.append(event)
        }
        let events = await collector.events

        #expect(events.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(telemetry.firstPartialLatencySeconds != nil)
        #expect(telemetry.processedAudioSeconds > 0)
    }

    private static func loadMonoAudio(at url: URL) throws -> (sampleRate: Double, samples: [Float]) {
        let file = try AVAudioFile(forReading: url)
        let capacity = AVAudioFrameCount(file.length)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: capacity
        ))
        try file.read(into: buffer)
        let channels = try #require(buffer.floatChannelData)
        let channelCount = max(1, Int(buffer.format.channelCount))
        let frameCount = Int(buffer.frameLength)
        var mono = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                mono[frame] += channels[channel][frame] / Float(channelCount)
            }
        }
        return (buffer.format.sampleRate, mono)
    }
}

private actor RealModelDraftCollector {
    private(set) var events: [OnlineDraftEvent] = []

    func append(_ event: OnlineDraftEvent) {
        events.append(event)
    }
}
