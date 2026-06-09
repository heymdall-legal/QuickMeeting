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
    nonisolated static let hardcodedHuggingFaceToken = "hardcoded-token"

    private let meetingStore: MeetingStore
    private let progressCenter: TranscriptionProgressCenter
    private let launcher: any SidecarProcessLaunching
    private let eventDecoder: SidecarTranscriptionEventDecoder
    private let executableURLProvider: @Sendable () -> URL?
    private let hfTokenProvider: @Sendable () -> String
    private let hfHomeURLProvider: @Sendable () -> URL
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private var activeMeetingID: UUID?

    init(
        meetingStore: MeetingStore,
        progressCenter: TranscriptionProgressCenter,
        launcher: any SidecarProcessLaunching,
        eventDecoder: SidecarTranscriptionEventDecoder = SidecarTranscriptionEventDecoder(),
        executableURLProvider: @escaping @Sendable () -> URL?,
        hfTokenProvider: @escaping @Sendable () -> String,
        hfHomeURLProvider: @escaping @Sendable () -> URL,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.meetingStore = meetingStore
        self.progressCenter = progressCenter
        self.launcher = launcher
        self.eventDecoder = eventDecoder
        self.executableURLProvider = executableURLProvider
        self.hfTokenProvider = hfTokenProvider
        self.hfHomeURLProvider = hfHomeURLProvider
        self.fileManager = fileManager
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

        activeMeetingID = meetingID
        try meetingStore.startTranscription(meetingID: meetingID, updatedAt: dateProvider())
        progressCenter.startTracking(meetingID: meetingID)

        defer {
            progressCenter.finishTracking(meetingID: meetingID)
            activeMeetingID = nil
        }

        do {
            let runState = SidecarTranscriptionRunState()
            try await launcher.run(
                SidecarLaunchRequest(
                    executableURL: executableURL,
                    arguments: [
                        "--input-file",
                        audioFileURL.path,
                        "--hf-token",
                        hfTokenProvider(),
                    ],
                    environment: [
                        "HF_HOME": hfHomeURLProvider().path,
                    ]
                )
            ) { [self] line in
                try await consume(line: line, meetingID: meetingID, runState: runState)
            }

            guard let completedPayload = await runState.completedPayload else {
                throw SidecarLaunchError.terminatedWithoutTerminalEvent
            }

            let transcript = makeStoredTranscript(from: completedPayload)
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
                progressCenter.startDiarizationTracking(meetingID: meetingID)
            }
            progressCenter.updateDiarizationProgress(Double(progress.percent) / 100, for: meetingID)
        case .completed(let payload):
            await runState.setCompletedPayload(payload)
        case .error(let payload):
            throw SidecarLaunchError.sidecarReported(payload.reason)
        }
    }

    private func makeStoredTranscript(from payload: SidecarCompletedPayload) -> StoredTranscript {
        let orderedSpeakerIDs = payload.segments.reduce(into: [String]()) { result, segment in
            guard !result.contains(segment.speaker) else {
                return
            }

            result.append(segment.speaker)
        }
        let speakers = orderedSpeakerIDs.enumerated().map { index, speakerID in
            TranscriptSpeaker(id: speakerID, displayName: "Speaker \(index + 1)")
        }
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
        bundle.resourceURL?
            .appendingPathComponent("example", isDirectory: true)
            .appendingPathComponent("example", isDirectory: false)
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
}

private actor SidecarTranscriptionRunState {
    var completedPayload: SidecarCompletedPayload?

    func setCompletedPayload(_ payload: SidecarCompletedPayload) {
        completedPayload = payload
    }
}
