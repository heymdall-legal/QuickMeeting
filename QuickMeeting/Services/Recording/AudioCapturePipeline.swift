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
        func append(_ sampleBuffer: CMSampleBuffer) throws
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
            captureConfiguration: CaptureConfiguration()
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
            let createdOutputSink = CaptureOutputSink(writer: writer)
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
    private var storedError: Error?
    private var sampleBufferCount = 0
    private var firstSampleSeconds: Double?
    private var lastSampleSeconds: Double?

    init(writer: any NativeAudioCapturePipeline.AudioFileWriting) {
        self.writer = writer
    }

    func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else {
            return
        }

        guard storedError == nil else {
            return
        }

        do {
            try writer?.append(sampleBuffer)
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
                    try self.writer?.finish()
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

        try stream.addStreamOutput(
            outputSink,
            type: .audio,
            sampleHandlerQueue: outputSink.sampleHandlerQueue
        )

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
    private static let canonicalFormat = AVAudioFormat(
        standardFormatWithSampleRate: 48_000,
        channels: 2
    )!

    private let outputURL: URL
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?

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
            settings: Self.canonicalFormat.settings,
            commonFormat: Self.canonicalFormat.commonFormat,
            interleaved: Self.canonicalFormat.isInterleaved
        )
    }

    func append(_ sampleBuffer: CMSampleBuffer) throws {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        let sourceBuffer = try sampleBuffer.makePCMBuffer()
        let bufferToWrite = try canonicalBuffer(from: sourceBuffer)

        guard bufferToWrite.frameLength > 0 else {
            return
        }

        try audioFile?.write(from: bufferToWrite)
    }

    func finish() throws {
        audioFile = nil
        converter = nil
    }

    private func canonicalBuffer(from sourceBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard sourceBuffer.frameLength > 0 else {
            return sourceBuffer
        }

        if formatsMatch(sourceBuffer.format, Self.canonicalFormat) {
            return sourceBuffer
        }

        guard let converter = converter ?? AVAudioConverter(from: sourceBuffer.format, to: Self.canonicalFormat) else {
            throw NativeAudioCapturePipelineError.audioConversionFailed
        }

        self.converter = converter

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
