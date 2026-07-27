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
        #expect(writer.firstChannelFirstSamples == [0.75])
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
