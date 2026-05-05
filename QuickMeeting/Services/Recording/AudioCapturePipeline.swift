//
//  AudioCapturePipeline.swift
//  QuickMeeting
//
//  Created by Codex on 04.05.2026.
//

import AVFAudio
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

protocol AudioCapturePipeline {
    func start(outputURL: URL) async throws
    func stop() async throws
}

private enum CapturedAudioSource {
    case system
    case microphone
}

enum NativeAudioCapturePipelineError: LocalizedError {
    case captureAlreadyRunning
    case noShareableDisplay
    case invalidAudioSampleBuffer
    case audioBufferCopyFailed(OSStatus)
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .captureAlreadyRunning:
            "Audio capture is already running."
        case .noShareableDisplay:
            "No shareable display is available for audio capture."
        case .invalidAudioSampleBuffer:
            "The audio capture pipeline received an invalid audio sample buffer."
        case .audioBufferCopyFailed(let status):
            "Copying captured PCM audio failed with status \(status)."
        case .audioConversionFailed:
            "Converting captured audio into the canonical WAV format failed."
        }
    }
}

@MainActor
final class NativeAudioCapturePipeline: AudioCapturePipeline {
    enum RecordingDiagnosticEvent: Equatable {
        case writerPrepared
        case captureStarted
        case captureStartFailed
        case captureStopped
        case captureStopFailed
    }

    struct RecordingDiagnostics: Equatable {
        let event: RecordingDiagnosticEvent
        let outputURL: URL
        let sampleBufferCount: Int
        let firstSampleSeconds: Double?
        let lastSampleSeconds: Double?
        let fileExists: Bool
        let fileSizeBytes: UInt64?
        let errorDescription: String?
    }

    struct CaptureConfiguration: Equatable {
        let sampleRate: Double
        let channelCount: Int
        let capturesSystemAudio: Bool
        let capturesMicrophone: Bool

        init(
            sampleRate: Double = 48_000,
            channelCount: Int = 2,
            capturesSystemAudio: Bool = true,
            capturesMicrophone: Bool = false
        ) {
            self.sampleRate = sampleRate
            self.channelCount = channelCount
            self.capturesSystemAudio = capturesSystemAudio
            self.capturesMicrophone = capturesMicrophone
        }
    }

    struct CaptureTarget {
        let width: Int
        let height: Int
        let makeSession: (CaptureConfiguration, CaptureOutputSink) throws -> any AudioCaptureStreamSession
    }

    protocol AudioCaptureStreamSession: AnyObject {
        func start() async throws
        func stop() async throws
    }

    protocol AudioFileWriting: AnyObject {
        func append(_ buffer: AVAudioPCMBuffer) throws
        func finish() throws
    }

    private enum State {
        case idle
        case capturing(
            session: any AudioCaptureStreamSession,
            outputSink: CaptureOutputSink,
            outputURL: URL
        )
        case stopping(
            session: any AudioCaptureStreamSession,
            outputSink: CaptureOutputSink,
            outputURL: URL,
            nativeStopCompleted: Bool
        )
    }

    private let shareableContentProvider: () async throws -> CaptureTarget
    private let writerFactory: (URL) throws -> any AudioFileWriting
    private let captureConfiguration: CaptureConfiguration
    private let diagnosticHandler: @Sendable (RecordingDiagnostics) -> Void
    private var state: State = .idle
    private let logger = Logger(subsystem: "info.akitov.QuickMeeting", category: "Recording")

    init(
        shareableContentProvider: @escaping () async throws -> CaptureTarget,
        writerFactory: @escaping (URL) throws -> any AudioFileWriting,
        captureConfiguration: CaptureConfiguration,
        diagnosticHandler: @escaping @Sendable (RecordingDiagnostics) -> Void = { _ in }
    ) {
        self.shareableContentProvider = shareableContentProvider
        self.writerFactory = writerFactory
        self.captureConfiguration = captureConfiguration
        self.diagnosticHandler = diagnosticHandler
    }

    convenience init() {
        self.init(
            shareableContentProvider: { try await Self.makeLiveCaptureTarget() },
            writerFactory: { try CanonicalWAVAudioFileWriter(outputURL: $0) },
            captureConfiguration: CaptureConfiguration(capturesMicrophone: true)
        )
    }

    func start(outputURL: URL) async throws {
        guard case .idle = state else {
            throw NativeAudioCapturePipelineError.captureAlreadyRunning
        }

        let writer = try writerFactory(outputURL)
        emitDiagnostics(
            event: .writerPrepared,
            outputURL: outputURL,
            captureDiagnostics: nil,
            error: nil
        )
        var outputSink: CaptureOutputSink?

        do {
            let target = try await shareableContentProvider()
            let createdOutputSink = CaptureOutputSink(
                writer: writer,
                captureConfiguration: captureConfiguration
            )
            outputSink = createdOutputSink
            let session = try target.makeSession(captureConfiguration, createdOutputSink)

            state = .capturing(
                session: session,
                outputSink: createdOutputSink,
                outputURL: outputURL
            )

            try await session.start()
            emitDiagnostics(
                event: .captureStarted,
                outputURL: outputURL,
                captureDiagnostics: nil,
                error: nil
            )
        } catch {
            let currentOutputSink = outputSink ?? activeOutputSink
            state = .idle

            if let currentOutputSink {
                let captureDiagnostics = try? await currentOutputSink.finish()
                emitDiagnostics(
                    event: .captureStartFailed,
                    outputURL: outputURL,
                    captureDiagnostics: captureDiagnostics,
                    error: error
                )
            } else {
                try? writer.finish()
                emitDiagnostics(
                    event: .captureStartFailed,
                    outputURL: outputURL,
                    captureDiagnostics: nil,
                    error: error
                )
            }

            throw error
        }
    }

    func stop() async throws {
        switch state {
        case .idle:
            return
        case .capturing(let session, let outputSink, let outputURL):
            state = .stopping(
                session: session,
                outputSink: outputSink,
                outputURL: outputURL,
                nativeStopCompleted: false
            )
            try await continueStopping()
        case .stopping:
            try await continueStopping()
        }
    }

    private var activeOutputSink: CaptureOutputSink? {
        switch state {
        case .idle:
            nil
        case .capturing(_, let outputSink, _), .stopping(_, let outputSink, _, _):
            outputSink
        }
    }

    private func continueStopping() async throws {
        guard case .stopping(let session, let outputSink, let outputURL, let nativeStopCompleted) = state else {
            return
        }

        if !nativeStopCompleted {
            try await session.stop()
            state = .stopping(
                session: session,
                outputSink: outputSink,
                outputURL: outputURL,
                nativeStopCompleted: true
            )
        }

        do {
            let captureDiagnostics = try await outputSink.finish()
            state = .idle
            emitDiagnostics(
                event: .captureStopped,
                outputURL: outputURL,
                captureDiagnostics: captureDiagnostics,
                error: nil
            )
        } catch {
            let captureDiagnostics = await outputSink.currentDiagnostics()
            emitDiagnostics(
                event: .captureStopFailed,
                outputURL: outputURL,
                captureDiagnostics: captureDiagnostics,
                error: error
            )
            throw error
        }
    }

    private func emitDiagnostics(
        event: RecordingDiagnosticEvent,
        outputURL: URL,
        captureDiagnostics: CaptureOutputDiagnostics?,
        error: Error?
    ) {
        let fileMetadata = fileMetadata(for: outputURL)
        let diagnostics = RecordingDiagnostics(
            event: event,
            outputURL: outputURL,
            sampleBufferCount: captureDiagnostics?.sampleBufferCount ?? 0,
            firstSampleSeconds: captureDiagnostics?.firstSampleSeconds,
            lastSampleSeconds: captureDiagnostics?.lastSampleSeconds,
            fileExists: fileMetadata.exists,
            fileSizeBytes: fileMetadata.fileSizeBytes,
            errorDescription: error?.localizedDescription ?? captureDiagnostics?.storedErrorDescription
        )

        logger.info(
            """
            event=\(String(describing: diagnostics.event), privacy: .public) outputURL=\(diagnostics.outputURL.path(), privacy: .public) \
            sampleBufferCount=\(diagnostics.sampleBufferCount) firstSampleSeconds=\(String(describing: diagnostics.firstSampleSeconds), privacy: .public) \
            lastSampleSeconds=\(String(describing: diagnostics.lastSampleSeconds), privacy: .public) fileExists=\(diagnostics.fileExists) \
            fileSizeBytes=\(String(describing: diagnostics.fileSizeBytes), privacy: .public) error=\(diagnostics.errorDescription ?? "none", privacy: .public)
            """
        )
        diagnosticHandler(diagnostics)
    }

    private func fileMetadata(for outputURL: URL) -> (exists: Bool, fileSizeBytes: UInt64?) {
        let fileManager = FileManager.default
        let path = outputURL.path()

        guard fileManager.fileExists(atPath: path) else {
            return (false, nil)
        }

        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let fileSize = attributes?[.size] as? NSNumber
        return (true, fileSize?.uint64Value)
    }

    private static func makeLiveCaptureTarget() async throws -> CaptureTarget {
        let shareableContent: SCShareableContent = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<SCShareableContent, Error>) in
            SCShareableContent.getExcludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            ) { shareableContent, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let shareableContent else {
                    continuation.resume(throwing: NativeAudioCapturePipelineError.noShareableDisplay)
                    return
                }

                continuation.resume(returning: shareableContent)
            }
        }

        guard let display = shareableContent.displays.first else {
            throw NativeAudioCapturePipelineError.noShareableDisplay
        }

        return CaptureTarget(width: display.width, height: display.height) { configuration, outputSink in
            try ScreenCaptureAudioStreamSession(
                display: display,
                displayWidth: display.width,
                displayHeight: display.height,
                captureConfiguration: configuration,
                outputSink: outputSink
            )
        }
    }
}

struct CaptureOutputDiagnostics {
    let sampleBufferCount: Int
    let firstSampleSeconds: Double?
    let lastSampleSeconds: Double?
    let storedErrorDescription: String?
}

final class CaptureOutputSink: NSObject, SCStreamOutput, SCStreamDelegate {
    let sampleHandlerQueue = DispatchQueue(
        label: "info.akitov.QuickMeeting.NativeAudioCapturePipeline.audio-output"
    )

    private var writer: (any NativeAudioCapturePipeline.AudioFileWriting)?
    private let mixer: CapturedAudioMixer
    private var storedError: Error?
    private var sampleBufferCount = 0
    private var firstSampleSeconds: Double?
    private var lastSampleSeconds: Double?

    init(
        writer: any NativeAudioCapturePipeline.AudioFileWriting,
        captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration = .init()
    ) {
        self.writer = writer
        mixer = CapturedAudioMixer(
            writer: writer,
            capturesSystemAudio: captureConfiguration.capturesSystemAudio,
            capturesMicrophone: captureConfiguration.capturesMicrophone
        )
    }

    func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard let source = capturedAudioSource(for: outputType) else {
            return
        }

        guard storedError == nil else {
            return
        }

        do {
            try mixer.append(
                sampleBuffer,
                presentationTimeSeconds: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds,
                source: source
            )
            sampleBufferCount += 1

            let presentationTimeSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            if presentationTimeSeconds.isFinite {
                if firstSampleSeconds == nil {
                    firstSampleSeconds = presentationTimeSeconds
                }
                lastSampleSeconds = presentationTimeSeconds
            }
        } catch {
            storedError = error
        }
    }

    func appendForTesting(
        _ buffer: AVAudioPCMBuffer,
        presentationTimeSeconds: Double,
        outputType: SCStreamOutputType
    ) throws {
        guard let source = capturedAudioSource(for: outputType) else {
            return
        }

        try mixer.append(
            buffer,
            presentationTimeSeconds: presentationTimeSeconds,
            source: source
        )
        sampleBufferCount += 1

        if firstSampleSeconds == nil {
            firstSampleSeconds = presentationTimeSeconds
        }
        lastSampleSeconds = presentationTimeSeconds
    }

    func stream(_: SCStream, didStopWithError error: any Error) {
        sampleHandlerQueue.async {
            guard self.storedError == nil else {
                return
            }

            self.storedError = error
        }
    }

    func finish() async throws -> CaptureOutputDiagnostics {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<CaptureOutputDiagnostics, Error>) in
            sampleHandlerQueue.async {
                let completionError = self.storedError
                let diagnostics = CaptureOutputDiagnostics(
                    sampleBufferCount: self.sampleBufferCount,
                    firstSampleSeconds: self.firstSampleSeconds,
                    lastSampleSeconds: self.lastSampleSeconds,
                    storedErrorDescription: completionError?.localizedDescription
                )
                self.storedError = nil
                self.sampleBufferCount = 0
                self.firstSampleSeconds = nil
                self.lastSampleSeconds = nil

                do {
                    try self.mixer.finish()
                } catch {
                    self.writer = nil
                    continuation.resume(throwing: error)
                    return
                }

                self.writer = nil

                if let completionError {
                    continuation.resume(throwing: completionError)
                } else {
                    continuation.resume(returning: diagnostics)
                }
            }
        }
    }

    func currentDiagnostics() async -> CaptureOutputDiagnostics {
        await withCheckedContinuation { continuation in
            sampleHandlerQueue.async {
                continuation.resume(
                    returning: CaptureOutputDiagnostics(
                        sampleBufferCount: self.sampleBufferCount,
                        firstSampleSeconds: self.firstSampleSeconds,
                        lastSampleSeconds: self.lastSampleSeconds,
                        storedErrorDescription: self.storedError?.localizedDescription
                    )
                )
            }
        }
    }

    private func capturedAudioSource(for outputType: SCStreamOutputType) -> CapturedAudioSource? {
        switch outputType {
        case .audio:
            .system
        case .microphone:
            .microphone
        default:
            nil
        }
    }
}

private final class CapturedAudioMixer {
    private static let mixAlignmentToleranceSeconds = 0.01

    private let writer: any NativeAudioCapturePipeline.AudioFileWriting
    private let capturesSystemAudio: Bool
    private let capturesMicrophone: Bool
    private let converter = CanonicalAudioBufferConverter()
    private var systemQueue: [TimestampedPCMBuffer] = []
    private var microphoneQueue: [TimestampedPCMBuffer] = []
    private var latestSystemEndTimeSeconds: Double?
    private var latestMicrophoneEndTimeSeconds: Double?

    init(
        writer: any NativeAudioCapturePipeline.AudioFileWriting,
        capturesSystemAudio: Bool,
        capturesMicrophone: Bool
    ) {
        self.writer = writer
        self.capturesSystemAudio = capturesSystemAudio
        self.capturesMicrophone = capturesMicrophone
    }

    func append(
        _ sampleBuffer: CMSampleBuffer,
        presentationTimeSeconds: Double,
        source: CapturedAudioSource
    ) throws {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        try append(
            sampleBuffer.makePCMBuffer(),
            presentationTimeSeconds: presentationTimeSeconds,
            source: source
        )
    }

    func append(
        _ buffer: AVAudioPCMBuffer,
        presentationTimeSeconds: Double,
        source: CapturedAudioSource
    ) throws {
        let canonicalBuffer = try converter.canonicalBuffer(from: buffer)

        if shouldPassthroughSoloSource(for: source) {
            try writer.append(canonicalBuffer)
            return
        }

        let timestampedBuffer = TimestampedPCMBuffer(
            presentationTimeSeconds: presentationTimeSeconds,
            buffer: canonicalBuffer
        )
        enqueue(timestampedBuffer, for: source)
        try flushReadyBuffers(force: false)
    }

    func finish() throws {
        try flushReadyBuffers(force: true)
        try writer.finish()
    }

    private func shouldPassthroughSoloSource(for source: CapturedAudioSource) -> Bool {
        switch source {
        case .system:
            capturesSystemAudio && !capturesMicrophone
        case .microphone:
            capturesMicrophone && !capturesSystemAudio
        }
    }

    private func enqueue(
        _ timestampedBuffer: TimestampedPCMBuffer,
        for source: CapturedAudioSource
    ) {
        switch source {
        case .system:
            systemQueue.append(timestampedBuffer)
            latestSystemEndTimeSeconds = max(
                latestSystemEndTimeSeconds ?? timestampedBuffer.endTimeSeconds,
                timestampedBuffer.endTimeSeconds
            )
        case .microphone:
            microphoneQueue.append(timestampedBuffer)
            latestMicrophoneEndTimeSeconds = max(
                latestMicrophoneEndTimeSeconds ?? timestampedBuffer.endTimeSeconds,
                timestampedBuffer.endTimeSeconds
            )
        }
    }

    private func flushReadyBuffers(force: Bool) throws {
        while true {
            let systemHead = systemQueue.first
            let microphoneHead = microphoneQueue.first

            switch (systemHead, microphoneHead) {
            case (nil, nil):
                return
            case let (systemHead?, nil):
                guard force || canFlushSolo(
                    systemHead,
                    otherLatestEndTimeSeconds: latestMicrophoneEndTimeSeconds
                ) else {
                    return
                }

                try writer.append(systemHead.buffer)
                systemQueue.removeFirst()
            case let (nil, microphoneHead?):
                guard force || canFlushSolo(
                    microphoneHead,
                    otherLatestEndTimeSeconds: latestSystemEndTimeSeconds
                ) else {
                    return
                }

                try writer.append(microphoneHead.buffer)
                microphoneQueue.removeFirst()
            case let (systemHead?, microphoneHead?):
                if systemHead.presentationTimeSeconds + Self.mixAlignmentToleranceSeconds
                    < microphoneHead.presentationTimeSeconds {
                    let splitTime = min(microphoneHead.presentationTimeSeconds, systemHead.endTimeSeconds)
                    let prefix = try splitPrefix(
                        from: systemHead,
                        until: splitTime
                    )

                    if prefix.consumedAllFrames {
                        if force || canFlushSolo(
                            systemHead,
                            otherLatestEndTimeSeconds: latestMicrophoneEndTimeSeconds
                        ) {
                            try writer.append(prefix.prefixBuffer)
                            systemQueue.removeFirst()
                            continue
                        }

                        return
                    }

                    try writer.append(prefix.prefixBuffer)
                    systemQueue[0] = prefix.remainder
                    continue
                }

                if microphoneHead.presentationTimeSeconds + Self.mixAlignmentToleranceSeconds
                    < systemHead.presentationTimeSeconds {
                    let splitTime = min(systemHead.presentationTimeSeconds, microphoneHead.endTimeSeconds)
                    let prefix = try splitPrefix(
                        from: microphoneHead,
                        until: splitTime
                    )

                    if prefix.consumedAllFrames {
                        if force || canFlushSolo(
                            microphoneHead,
                            otherLatestEndTimeSeconds: latestSystemEndTimeSeconds
                        ) {
                            try writer.append(prefix.prefixBuffer)
                            microphoneQueue.removeFirst()
                            continue
                        }

                        return
                    }

                    try writer.append(prefix.prefixBuffer)
                    microphoneQueue[0] = prefix.remainder
                    continue
                }

                let overlappedFrameCount = min(
                    systemHead.buffer.frameLength,
                    microphoneHead.buffer.frameLength
                )
                let mixedBuffer = try mix(
                    systemBuffer: systemHead.buffer,
                    microphoneBuffer: microphoneHead.buffer,
                    frameCount: overlappedFrameCount
                )
                try writer.append(mixedBuffer)

                updateQueueAfterConsumingFrames(
                    for: &systemQueue,
                    consumedFrameCount: overlappedFrameCount
                )
                updateQueueAfterConsumingFrames(
                    for: &microphoneQueue,
                    consumedFrameCount: overlappedFrameCount
                )
            }
        }
    }

    private func canFlushSolo(
        _ buffer: TimestampedPCMBuffer,
        otherLatestEndTimeSeconds: Double?
    ) -> Bool {
        guard let otherLatestEndTimeSeconds else {
            return false
        }

        return buffer.endTimeSeconds <= otherLatestEndTimeSeconds + Self.mixAlignmentToleranceSeconds
    }

    private func splitPrefix(
        from timestampedBuffer: TimestampedPCMBuffer,
        until splitTimeSeconds: Double
    ) throws -> BufferSplitResult {
        let secondsToConsume = max(0, splitTimeSeconds - timestampedBuffer.presentationTimeSeconds)
        let frameCount = min(
            AVAudioFrameCount(
                floor(secondsToConsume * CanonicalAudioBufferConverter.canonicalFormat.sampleRate)
            ),
            timestampedBuffer.buffer.frameLength
        )

        if frameCount == 0 {
            return BufferSplitResult(
                prefixBuffer: try sliceBuffer(
                    timestampedBuffer.buffer,
                    offsetFrames: 0,
                    frameCount: timestampedBuffer.buffer.frameLength
                ),
                remainder: timestampedBuffer,
                consumedAllFrames: false
            )
        }

        let prefixBuffer = try sliceBuffer(
            timestampedBuffer.buffer,
            offsetFrames: 0,
            frameCount: frameCount
        )

        guard frameCount < timestampedBuffer.buffer.frameLength else {
            return BufferSplitResult(
                prefixBuffer: prefixBuffer,
                remainder: timestampedBuffer,
                consumedAllFrames: true
            )
        }

        let remainderBuffer = try sliceBuffer(
            timestampedBuffer.buffer,
            offsetFrames: frameCount,
            frameCount: timestampedBuffer.buffer.frameLength - frameCount
        )
        let remainder = TimestampedPCMBuffer(
            presentationTimeSeconds: timestampedBuffer.presentationTimeSeconds
                + Double(frameCount) / CanonicalAudioBufferConverter.canonicalFormat.sampleRate,
            buffer: remainderBuffer
        )

        return BufferSplitResult(
            prefixBuffer: prefixBuffer,
            remainder: remainder,
            consumedAllFrames: false
        )
    }

    private func updateQueueAfterConsumingFrames(
        for queue: inout [TimestampedPCMBuffer],
        consumedFrameCount: AVAudioFrameCount
    ) {
        guard let head = queue.first else {
            return
        }

        if consumedFrameCount >= head.buffer.frameLength {
            queue.removeFirst()
            return
        }

        do {
            let remainderBuffer = try sliceBuffer(
                head.buffer,
                offsetFrames: consumedFrameCount,
                frameCount: head.buffer.frameLength - consumedFrameCount
            )
            queue[0] = TimestampedPCMBuffer(
                presentationTimeSeconds: head.presentationTimeSeconds
                    + Double(consumedFrameCount) / CanonicalAudioBufferConverter.canonicalFormat.sampleRate,
                buffer: remainderBuffer
            )
        } catch {
            queue.removeFirst()
        }
    }

    private func mix(
        systemBuffer: AVAudioPCMBuffer,
        microphoneBuffer: AVAudioPCMBuffer,
        frameCount: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        guard let mixedBuffer = AVAudioPCMBuffer(
            pcmFormat: CanonicalAudioBufferConverter.canonicalFormat,
            frameCapacity: frameCount
        ) else {
            throw NativeAudioCapturePipelineError.audioConversionFailed
        }

        mixedBuffer.frameLength = frameCount

        guard let mixedChannelData = mixedBuffer.floatChannelData,
              let systemChannelData = systemBuffer.floatChannelData,
              let microphoneChannelData = microphoneBuffer.floatChannelData else {
            throw NativeAudioCapturePipelineError.audioConversionFailed
        }

        for channelIndex in 0 ..< Int(CanonicalAudioBufferConverter.canonicalFormat.channelCount) {
            for frameIndex in 0 ..< Int(frameCount) {
                let mixedSample = systemChannelData[channelIndex][frameIndex]
                    + microphoneChannelData[channelIndex][frameIndex]
                mixedChannelData[channelIndex][frameIndex] = min(max(mixedSample, -1), 1)
            }
        }

        return mixedBuffer
    }

    private func sliceBuffer(
        _ buffer: AVAudioPCMBuffer,
        offsetFrames: AVAudioFrameCount,
        frameCount: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        guard let slicedBuffer = AVAudioPCMBuffer(
            pcmFormat: CanonicalAudioBufferConverter.canonicalFormat,
            frameCapacity: frameCount
        ) else {
            throw NativeAudioCapturePipelineError.audioConversionFailed
        }

        slicedBuffer.frameLength = frameCount

        guard let sourceChannelData = buffer.floatChannelData,
              let slicedChannelData = slicedBuffer.floatChannelData else {
            throw NativeAudioCapturePipelineError.audioConversionFailed
        }

        for channelIndex in 0 ..< Int(CanonicalAudioBufferConverter.canonicalFormat.channelCount) {
            for frameIndex in 0 ..< Int(frameCount) {
                slicedChannelData[channelIndex][frameIndex] =
                    sourceChannelData[channelIndex][Int(offsetFrames) + frameIndex]
            }
        }

        return slicedBuffer
    }
}

private struct BufferSplitResult {
    let prefixBuffer: AVAudioPCMBuffer
    let remainder: TimestampedPCMBuffer
    let consumedAllFrames: Bool
}

private struct TimestampedPCMBuffer {
    let presentationTimeSeconds: Double
    let buffer: AVAudioPCMBuffer

    var endTimeSeconds: Double {
        presentationTimeSeconds
            + Double(buffer.frameLength) / CanonicalAudioBufferConverter.canonicalFormat.sampleRate
    }
}

private final class ScreenCaptureAudioStreamSession: NativeAudioCapturePipeline.AudioCaptureStreamSession {
    private let stream: SCStream

    init(
        display: SCDisplay,
        displayWidth: Int,
        displayHeight: Int,
        captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration,
        outputSink: CaptureOutputSink
    ) throws {
        let contentFilter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = max(displayWidth, 2)
        configuration.height = max(displayHeight, 2)
        configuration.capturesAudio = captureConfiguration.capturesSystemAudio
        configuration.sampleRate = Int(captureConfiguration.sampleRate)
        configuration.channelCount = captureConfiguration.channelCount
        configuration.excludesCurrentProcessAudio = false
        configuration.captureMicrophone = captureConfiguration.capturesMicrophone

        let stream = SCStream(
            filter: contentFilter,
            configuration: configuration,
            delegate: outputSink
        )

        if captureConfiguration.capturesSystemAudio {
            try stream.addStreamOutput(
                outputSink,
                type: .audio,
                sampleHandlerQueue: outputSink.sampleHandlerQueue
            )
        }

        if captureConfiguration.capturesMicrophone {
            try stream.addStreamOutput(
                outputSink,
                type: .microphone,
                sampleHandlerQueue: outputSink.sampleHandlerQueue
            )
        }

        self.stream = stream
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func stop() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private final class CanonicalWAVAudioFileWriter: NativeAudioCapturePipeline.AudioFileWriting {
    private let outputURL: URL
    private var audioFile: AVAudioFile?

    init(outputURL: URL) throws {
        self.outputURL = outputURL

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: outputURL.path()) {
            try fileManager.removeItem(at: outputURL)
        }

        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: CanonicalAudioBufferConverter.canonicalFormat.settings,
            commonFormat: CanonicalAudioBufferConverter.canonicalFormat.commonFormat,
            interleaved: CanonicalAudioBufferConverter.canonicalFormat.isInterleaved
        )
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        guard buffer.frameLength > 0 else {
            return
        }

        try audioFile?.write(from: buffer)
    }

    func finish() throws {
        audioFile = nil
    }
}

private final class CanonicalAudioBufferConverter {
    static let canonicalFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 2,
        interleaved: false
    )!

    func canonicalBuffer(from sourceBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard sourceBuffer.frameLength > 0 else {
            return sourceBuffer
        }

        if formatsMatch(sourceBuffer.format, Self.canonicalFormat) {
            return sourceBuffer
        }

        guard let converter = AVAudioConverter(from: sourceBuffer.format, to: Self.canonicalFormat) else {
            throw NativeAudioCapturePipelineError.audioConversionFailed
        }

        let frameCapacity = max(
            AVAudioFrameCount(
                ceil(
                    Double(sourceBuffer.frameLength)
                        * (Self.canonicalFormat.sampleRate / sourceBuffer.format.sampleRate)
                )
            ),
            1
        )

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.canonicalFormat,
            frameCapacity: frameCapacity
        ) else {
            throw NativeAudioCapturePipelineError.audioConversionFailed
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outputStatus in
            if didProvideInput {
                outputStatus.pointee = .endOfStream
                return nil
            }

            didProvideInput = true
            outputStatus.pointee = .haveData
            return sourceBuffer
        }

        if let conversionError {
            throw conversionError
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return convertedBuffer
        case .error:
            throw NativeAudioCapturePipelineError.audioConversionFailed
        @unknown default:
            throw NativeAudioCapturePipelineError.audioConversionFailed
        }
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }
}

private extension CMSampleBuffer {
    func makePCMBuffer() throws -> AVAudioPCMBuffer {
        let frameCount = CMSampleBufferGetNumSamples(self)

        guard frameCount > 0,
              let formatDescription = CMSampleBufferGetFormatDescription(self),
              let pcmBuffer = AVAudioPCMBuffer(
                  pcmFormat: AVAudioFormat(cmAudioFormatDescription: formatDescription),
                  frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            throw NativeAudioCapturePipelineError.invalidAudioSampleBuffer
        }

        pcmBuffer.frameLength = pcmBuffer.frameCapacity

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )

        guard status == noErr else {
            throw NativeAudioCapturePipelineError.audioBufferCopyFailed(status)
        }

        return pcmBuffer
    }
}
