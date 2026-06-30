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

    func append(_: AVAudioPCMBuffer) throws {
        appendCallCount += 1
    }

    func finish() throws {
        finishCallCount += 1
    }
}
