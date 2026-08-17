import AVFAudio
import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct NativeAudioCapturePipelineTests {
    @Test
    func stopTimeoutStillFinishesAudioWriter() async throws {
        let session = HangingStopCaptureSession()
        let writer = SpyAudioFileWriter()
        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) { _, _ in
                    session
                }
            },
            writerFactory: { _ in writer },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration(capturesMicrophone: false),
            captureStopTimeout: 0.01
        )

        try await pipeline.start(outputURL: URL(fileURLWithPath: "/tmp/audio-\(UUID().uuidString).m4a"))
        try await pipeline.stop()

        #expect(session.startCallCount == 1)
        #expect(session.stopCallCount == 1)
        #expect(writer.finishCallCount == 1)
    }

    @Test
    func captureOutputSinkFinishesWhenTimestampPrecisionPreventsSplitting() async throws {
        let writer = SpyAudioFileWriter()
        let sink = CaptureOutputSink(
            writer: writer,
            captureConfiguration: .init(capturesMicrophone: true)
        )

        try sink.appendForTesting(
            makePCMBuffer(samples: [0.25, 0.25]),
            presentationTimeSeconds: -Double.greatestFiniteMagnitude,
            outputType: .audio
        )
        try sink.appendForTesting(
            makePCMBuffer(samples: [0.50, 0.50]),
            presentationTimeSeconds: 0,
            outputType: .microphone
        )

        _ = try await sink.finish()

        #expect(writer.finishCallCount == 1)
        #expect(writer.appendedFrameLengths == [2, 2])
        #expect(writer.appendCallCount == 2)
    }

    @Test
    func captureOutputSinkNormalizesNonFiniteTimestampsBeforeMixing() async throws {
        let writer = SpyAudioFileWriter()
        let sink = CaptureOutputSink(
            writer: writer,
            captureConfiguration: .init(capturesMicrophone: true)
        )

        try sink.appendForTesting(
            makePCMBuffer(samples: [0.25, 0.25]),
            presentationTimeSeconds: .infinity,
            outputType: .audio
        )
        try sink.appendForTesting(
            makePCMBuffer(samples: [0.50, 0.50]),
            presentationTimeSeconds: 0,
            outputType: .microphone
        )

        _ = try await sink.finish()

        #expect(writer.finishCallCount == 1)
        #expect(writer.appendedFrameLengths == [2])
        #expect(writer.firstChannelFirstSamples == [0.375])
    }

    @Test
    func captureOutputSinkPreservesIsolatedTracksAndMixesWithHeadroom() async throws {
        let previewWriter = SpyAudioFileWriter()
        let systemWriter = SpyAudioFileWriter()
        let microphoneWriter = SpyAudioFileWriter()
        let sink = CaptureOutputSink(
            writer: previewWriter,
            systemWriter: systemWriter,
            microphoneWriter: microphoneWriter,
            captureConfiguration: .init(capturesMicrophone: true)
        )

        try sink.appendForTesting(
            makePCMBuffer(samples: [1, 1]),
            presentationTimeSeconds: 0,
            outputType: .audio
        )
        try sink.appendForTesting(
            makePCMBuffer(samples: [1, 1]),
            presentationTimeSeconds: 0,
            outputType: .microphone
        )

        _ = try await sink.finish()

        #expect(systemWriter.firstChannelFirstSamples == [1])
        #expect(microphoneWriter.firstChannelFirstSamples == [1])
        #expect(previewWriter.firstChannelFirstSamples == [1])
        #expect(previewWriter.firstChannelFirstSamples.allSatisfy { abs($0) <= 1 })
        #expect(systemWriter.finishCallCount == 1)
        #expect(microphoneWriter.finishCallCount == 1)
    }

    @Test
    func isolatedTracksRemainTimelineAlignedAcrossSoloRegions() async throws {
        let previewWriter = SpyAudioFileWriter()
        let systemWriter = SpyAudioFileWriter()
        let microphoneWriter = SpyAudioFileWriter()
        let sink = CaptureOutputSink(
            writer: previewWriter,
            systemWriter: systemWriter,
            microphoneWriter: microphoneWriter,
            captureConfiguration: .init(capturesMicrophone: true)
        )

        try sink.appendForTesting(
            makePCMBuffer(samples: [0.8, 0.8]),
            presentationTimeSeconds: 0,
            outputType: .audio
        )
        try sink.appendForTesting(
            makePCMBuffer(samples: [0.2, 0.2]),
            presentationTimeSeconds: 1,
            outputType: .microphone
        )

        _ = try await sink.finish()

        #expect(systemWriter.firstChannelFirstSamples == [0.8, 0])
        #expect(microphoneWriter.firstChannelFirstSamples == [0, 0.2])
        #expect(previewWriter.firstChannelFirstSamples == [0.4, 0.1])
        #expect(systemWriter.appendedFrameLengths == microphoneWriter.appendedFrameLengths)
    }

    @Test
    func authoritativeWriterRunsBeforeBestEffortOnlineTee() async throws {
        let writer = SpyAudioFileWriter()
        let sinkProbe = OrderingOnlineAudioSink(writer: writer)
        let sink = CaptureOutputSink(
            writer: writer,
            captureConfiguration: .init(capturesMicrophone: false),
            onlineAudioSink: sinkProbe
        )

        try sink.appendForTesting(
            makePCMBuffer(samples: [0.25, -0.25]),
            presentationTimeSeconds: 7,
            outputType: .audio
        )
        _ = try await sink.finish()

        #expect(sinkProbe.writerWasCalledBeforeOffer)
        #expect(sinkProbe.receivedChunk?.startTime == 7)
        #expect(sinkProbe.receivedChunk?.sampleRate == 48_000)
        #expect(sinkProbe.receivedChunk?.samples == [0.25, -0.25])
    }

    @Test
    func losslessM4AWriterStoresCanonicalAudioAsAppleLossless() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quickmeeting-lossless-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let writer = try LosslessM4AAudioFileWriter(outputURL: outputURL)
        try writer.append(makePCMBuffer(samples: [0.25, -0.25]))
        try writer.finish()

        let audioFile = try AVAudioFile(forReading: outputURL)
        let streamDescription = audioFile.fileFormat.streamDescription
        #expect(streamDescription.pointee.mFormatID == kAudioFormatAppleLossless)
        #expect(audioFile.processingFormat.sampleRate == 48_000)
        #expect(audioFile.processingFormat.channelCount == 2)
    }

    private func makePCMBuffer(samples: [Float]) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        )
        let channelData = try #require(buffer.floatChannelData)
        buffer.frameLength = AVAudioFrameCount(samples.count)

        for (index, sample) in samples.enumerated() {
            channelData[0][index] = sample
            channelData[1][index] = sample
        }

        return buffer
    }
}

@MainActor
private final class HangingStopCaptureSession: NativeAudioCapturePipeline.AudioCaptureStreamSession {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start() async throws {
        startCallCount += 1
    }

    func stop() async throws {
        stopCallCount += 1
        try await Task.sleep(nanoseconds: 10_000_000_000)
    }
}

private final class SpyAudioFileWriter: NativeAudioCapturePipeline.AudioFileWriting {
    private(set) var appendCallCount = 0
    private(set) var finishCallCount = 0
    private(set) var appendedFrameLengths = [AVAudioFrameCount]()
    private(set) var firstChannelFirstSamples = [Float]()

    func append(_ buffer: AVAudioPCMBuffer) throws {
        appendCallCount += 1
        appendedFrameLengths.append(buffer.frameLength)
        if let firstChannel = buffer.floatChannelData?.pointee, buffer.frameLength > 0 {
            firstChannelFirstSamples.append(firstChannel[0])
        }
    }

    func finish() throws {
        finishCallCount += 1
    }
}

private final class OrderingOnlineAudioSink: OnlineAudioChunkSink, @unchecked Sendable {
    private let writer: SpyAudioFileWriter
    private(set) var writerWasCalledBeforeOffer = false
    private(set) var receivedChunk: TimestampedAudioChunk?

    init(writer: SpyAudioFileWriter) { self.writer = writer }

    func offer(_ chunk: TimestampedAudioChunk) -> Bool {
        writerWasCalledBeforeOffer = writer.appendCallCount == 1
        receivedChunk = chunk
        return true
    }
}
