import AVFoundation
import Foundation

enum SidecarTranscriptionServiceError: LocalizedError, Equatable {
    case bundledExecutableMissing
    case sidecarFailed(String)
    case invalidCompletedPayload

    var errorDescription: String? {
        switch self {
        case .bundledExecutableMissing:
            return "Bundled transcription helper is missing."
        case .sidecarFailed(let reason):
            return reason
        case .invalidCompletedPayload:
            return "Transcription helper returned an invalid result."
        }
    }
}

@MainActor
final class SidecarTranscriptionService: TranscriptionServicing {
    private let meetingStore: MeetingStore
    private let progressCenter: TranscriptionProgressCenter
    private let launcher: any SidecarProcessLaunching
    private let eventDecoder: SidecarTranscriptionEventDecoder
    private let executableURLProvider: @Sendable () -> URL?
    private let hfTokenProvider: @Sendable () -> String
    private let transcriptionLanguageProvider: @Sendable () -> TranscriptionLanguage
    private let initialPromptProvider: @Sendable () -> String
    private let hfHomeURLProvider: @Sendable () -> URL
    private let knownSpeakerStore: KnownSpeakerStore?
    private let knownSpeakerJSONWriter: KnownSpeakerJSONWriter
    private let recognitionMapper: SpeakerRecognitionMapper
    private let audioPreparer: any SidecarTranscriptionAudioPreparing
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private var activeMeetingID: UUID?

    init(
        meetingStore: MeetingStore,
        progressCenter: TranscriptionProgressCenter,
        launcher: any SidecarProcessLaunching,
        eventDecoder: SidecarTranscriptionEventDecoder? = nil,
        executableURLProvider: @escaping @Sendable () -> URL?,
        hfTokenProvider: @escaping @Sendable () -> String,
        transcriptionLanguageProvider: @escaping @Sendable () -> TranscriptionLanguage = { .none },
        initialPromptProvider: @escaping @Sendable () -> String = { "" },
        hfHomeURLProvider: @escaping @Sendable () -> URL,
        knownSpeakerStore: KnownSpeakerStore? = nil,
        knownSpeakerJSONWriter: KnownSpeakerJSONWriter = KnownSpeakerJSONWriter(),
        recognitionMapper: SpeakerRecognitionMapper = SpeakerRecognitionMapper(),
        audioPreparer: (any SidecarTranscriptionAudioPreparing)? = nil,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.meetingStore = meetingStore
        self.progressCenter = progressCenter
        self.launcher = launcher
        self.eventDecoder = eventDecoder ?? SidecarTranscriptionEventDecoder()
        self.executableURLProvider = executableURLProvider
        self.hfTokenProvider = hfTokenProvider
        self.transcriptionLanguageProvider = transcriptionLanguageProvider
        self.initialPromptProvider = initialPromptProvider
        self.hfHomeURLProvider = hfHomeURLProvider
        self.knownSpeakerStore = knownSpeakerStore
        self.knownSpeakerJSONWriter = knownSpeakerJSONWriter
        self.recognitionMapper = recognitionMapper
        self.fileManager = fileManager
        self.audioPreparer = audioPreparer ?? DefaultSidecarTranscriptionAudioPreparer(fileManager: fileManager)
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

        guard let executableURL = executableURLProvider() else {
            throw SidecarTranscriptionServiceError.bundledExecutableMissing
        }

        let huggingFaceToken = hfTokenProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !huggingFaceToken.isEmpty else {
            throw TranscriptionServiceError.missingHuggingFaceToken
        }
        let initialPrompt = initialPromptProvider().trimmingCharacters(in: .whitespacesAndNewlines)

        activeMeetingID = meetingID
        try meetingStore.startTranscription(meetingID: meetingID, updatedAt: dateProvider())
        progressCenter.startTracking(meetingID: meetingID)

        defer {
            progressCenter.finishTracking(meetingID: meetingID)
            activeMeetingID = nil
        }

        do {
            let preparedAudio = try await audioPreparer.prepareAudioFile(for: audioFileURL)
            defer {
                preparedAudio.cleanup()
            }
            let knownSpeakerFileURL = try makeKnownSpeakersFileIfNeeded()
            defer {
                if let knownSpeakerFileURL {
                    try? fileManager.removeItem(at: knownSpeakerFileURL)
                }
            }
            var arguments = [
                "main.py",
                "--input-file",
                preparedAudio.fileURL.path,
                "--hf-token",
                huggingFaceToken,
            ]
            if let languageArgument = transcriptionLanguageProvider().sidecarArgumentValue {
                arguments.append(contentsOf: ["--language", languageArgument])
            }
            if !initialPrompt.isEmpty {
                arguments.append(contentsOf: ["--initial-prompt", initialPrompt])
            }
            if let knownSpeakerFileURL {
                arguments.append(contentsOf: ["--known-speakers-file", knownSpeakerFileURL.path])
            }

            let runState = SidecarTranscriptionRunState()
            let workingDirectory = Self.pythonRootURL(for: executableURL)
            try await launcher.run(
                SidecarLaunchRequest(
                    executableURL: executableURL,
                    workingDirectoryURL: workingDirectory,
                    arguments: arguments,
                    environment: [
                        "HF_HOME": hfHomeURLProvider().path,
                        "MPLCONFIGDIR": NSTemporaryDirectory(),
                        "TMPDIR": NSTemporaryDirectory(),
                        "PYTHONPATH": workingDirectory
                            .appendingPathComponent(".venv", isDirectory: true) // .venv/lib/python3.12/site-packages/
                            .appendingPathComponent("lib", isDirectory: true) // .venv/lib/python3.12/site-packages/
                            .appendingPathComponent("python3.12", isDirectory: true) // .venv/lib/python3.12/site-packages/
                            .appendingPathComponent("site-packages", isDirectory: true) // .venv/lib/python3.12/site-packages/
                            .path()
                    ]
                )
            ) { [self] line in
                try await consume(line: line, meetingID: meetingID, runState: runState)
            }

            guard let completedPayload = await runState.completedPayload else {
                throw SidecarLaunchError.terminatedWithoutTerminalEvent
            }

            let transcript = try makeStoredTranscript(from: completedPayload)
            try meetingStore.completeTranscription(
                meetingID: meetingID,
                transcript: transcript,
                transcriptPreview: transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines),
                updatedAt: dateProvider()
            )
        } catch {
            try? meetingStore.failTranscription(meetingID: meetingID, updatedAt: dateProvider())
            throw map(error)
        }
    }

    private func makeKnownSpeakersFileIfNeeded() throws -> URL? {
        guard let knownSpeakerStore else {
            return nil
        }

        let exports = try knownSpeakerStore.allSpeakers()
            .map { speaker in
                KnownSpeakerExport(
                    id: speaker.id,
                    centroids: speaker.centroids
                        .sorted { $0.createdAt < $1.createdAt }
                        .map(\.values)
                )
            }
            .filter { !$0.centroids.isEmpty }

        guard !exports.isEmpty else {
            return nil
        }

        return try knownSpeakerJSONWriter.write(
            speakers: exports,
            directoryURL: fileManager.temporaryDirectory
        )
    }

    private func consume(
        line: String,
        meetingID: UUID,
        runState: SidecarTranscriptionRunState
    ) async throws {
        guard let event = try eventDecoder.decode(line: line) else {
            return
        }

        switch event {
        case .running:
            return
        case .downloading(let progress):
            progressCenter.updateProgress(Double(progress.percent) / 100, for: meetingID)
        case .transcribing(let progress):
            progressCenter.updateProgress(Double(progress.percent) / 100, for: meetingID)
        case .diarization(let progress):
            if progressCenter.diarizationProgress(for: meetingID) == nil {
                progressCenter.startDiarizationTracking(meetingID: meetingID, stepName: progress.step)
            }
            progressCenter.updateDiarizationProgress(
                Double(progress.percent) / 100,
                stepName: progress.step,
                for: meetingID
            )
        case .completed(let payload):
            await runState.setCompletedPayload(payload)
        case .error(let payload):
            throw SidecarLaunchError.sidecarReported(payload.reason)
        }
    }

    private func makeStoredTranscript(from payload: SidecarCompletedPayload) throws -> StoredTranscript {
        let knownSpeakerNamesByID = try Dictionary(
            uniqueKeysWithValues: (knownSpeakerStore?.allSpeakers() ?? []).map { ($0.id, $0.displayName) }
        )
        let speakers = recognitionMapper.makeTranscriptSpeakers(
            sidecarSpeakers: payload.speakers,
            segments: payload.segments,
            knownSpeakerNamesByID: knownSpeakerNamesByID
        )
        let segments = payload.segments.map { segment in
            TranscriptSegment(
                text: segment.text,
                startTime: segment.start,
                endTime: segment.end,
                speakerID: segment.speaker
            )
        }
        return StoredTranscript(speakers: speakers, segments: segments)
    }

    private func map(_ error: Error) -> Error {
        guard let launchError = error as? SidecarLaunchError else {
            return error
        }

        switch launchError {
        case .executableMissing:
            return SidecarTranscriptionServiceError.bundledExecutableMissing
        case .launchFailed(let message):
            return SidecarTranscriptionServiceError.sidecarFailed(message)
        case .terminatedWithoutTerminalEvent:
            return SidecarTranscriptionServiceError.sidecarFailed(
                "Transcription helper exited without returning a final result."
            )
        case .sidecarReported(let reason):
            return SidecarTranscriptionServiceError.sidecarFailed(reason)
        }
    }

    nonisolated static func defaultExecutableURL(bundle: Bundle = .main) -> URL? {
        let fileManager = FileManager.default
        let bundledURL = bundle.resourceURL?
            .appendingPathComponent("python", isDirectory: true)
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python", isDirectory: false)
        if let bundledURL, fileManager.fileExists(atPath: bundledURL.path) {
            return bundledURL
        }

        let fallbackURL = bundle.resourceURL?
            .appendingPathComponent("python", isDirectory: true)
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python", isDirectory: false)
        if let fallbackURL, fileManager.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }

        return bundledURL ?? fallbackURL
    }

    nonisolated static func defaultHFHomeURL(fileManager: FileManager = .default) -> URL {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupportURL
            .appendingPathComponent("QuickMeeting", isDirectory: true)
            .appendingPathComponent("HuggingFace", isDirectory: true)
    }

    private nonisolated static func pythonRootURL(for executableURL: URL) -> URL {
        executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private actor SidecarTranscriptionRunState {
    var completedPayload: SidecarCompletedPayload?

    func setCompletedPayload(_ payload: SidecarCompletedPayload) {
        completedPayload = payload
    }
}

struct PreparedSidecarTranscriptionAudio: Sendable {
    let fileURL: URL
    let cleanup: @Sendable () -> Void
}

protocol SidecarTranscriptionAudioPreparing: Sendable {
    func prepareAudioFile(for sourceURL: URL) async throws -> PreparedSidecarTranscriptionAudio
}

struct SidecarTranscriptionAudioPreparationError: LocalizedError {
    let operation: String
    let underlyingError: Error?

    var errorDescription: String? {
        if let underlyingError {
            return "\(operation): \(underlyingError.localizedDescription)"
        }

        return operation
    }
}

struct DefaultSidecarTranscriptionAudioPreparer: SidecarTranscriptionAudioPreparing {
    private static let wavFileSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: true,
    ]

    private static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepareAudioFile(for sourceURL: URL) async throws -> PreparedSidecarTranscriptionAudio {
        guard sourceURL.pathExtension.caseInsensitiveCompare("wav") != .orderedSame else {
            return PreparedSidecarTranscriptionAudio(fileURL: sourceURL, cleanup: {})
        }

        let wavURL = sourceURL.deletingPathExtension().appendingPathExtension("wav")
        if !fileManager.fileExists(atPath: wavURL.path) {
            try await convertToWAV(sourceURL: sourceURL, destinationURL: wavURL)
        }

        return PreparedSidecarTranscriptionAudio(fileURL: wavURL) {
            Self.removeItemIfPresent(at: wavURL)
        }
    }

    private func convertToWAV(sourceURL: URL, destinationURL: URL) async throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let track = try await Self.firstAudioTrack(in: asset)
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw SidecarTranscriptionAudioPreparationError(
                operation: "Failed to create audio reader",
                underlyingError: error
            )
        }

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: Self.wavFileSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw SidecarTranscriptionAudioPreparationError(
                operation: "Failed to attach audio reader output",
                underlyingError: nil
            )
        }
        reader.add(output)

        let destinationFile: AVAudioFile
        do {
            destinationFile = try AVAudioFile(
                forWriting: destinationURL,
                settings: Self.wavFileSettings,
                commonFormat: Self.outputFormat.commonFormat,
                interleaved: Self.outputFormat.isInterleaved
            )
        } catch {
            throw SidecarTranscriptionAudioPreparationError(
                operation: "Failed to open destination WAV file for writing",
                underlyingError: error
            )
        }

        guard reader.startReading() else {
            throw SidecarTranscriptionAudioPreparationError(
                operation: "Failed to start audio reader",
                underlyingError: reader.error
            )
        }

        var wroteFrames = false
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
                continue
            }

            let pcmBuffer: AVAudioPCMBuffer
            do {
                pcmBuffer = try Self.makePCMBuffer(from: sampleBuffer)
            } catch {
                throw SidecarTranscriptionAudioPreparationError(
                    operation: "Failed to decode source audio sample buffer",
                    underlyingError: error
                )
            }

            do {
                try destinationFile.write(from: pcmBuffer)
            } catch {
                throw SidecarTranscriptionAudioPreparationError(
                    operation: "Failed while writing converted WAV frames",
                    underlyingError: error
                )
            }
            wroteFrames = true
        }

        if reader.status == .failed {
            throw SidecarTranscriptionAudioPreparationError(
                operation: "Audio reader failed while decoding source audio",
                underlyingError: reader.error
            )
        }

        guard wroteFrames else {
            throw SidecarTranscriptionServiceError.invalidCompletedPayload
        }
    }

    private nonisolated static func removeItemIfPresent(at url: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try? fileManager.removeItem(at: url)
    }

    private static func firstAudioTrack(in asset: AVURLAsset) async throws -> AVAssetTrack {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw SidecarTranscriptionAudioPreparationError(
                operation: "Source audio file does not contain an audio track",
                underlyingError: nil
            )
        }

        return track
    }

    private static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
                let pcmBuffer = AVAudioPCMBuffer(
                  pcmFormat: AVAudioFormat(cmAudioFormatDescription: formatDescription),
                  frameCapacity: AVAudioFrameCount(frameCount)
              )
        else {
            throw SidecarTranscriptionServiceError.invalidCompletedPayload
        }

        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        return pcmBuffer
    }
}
