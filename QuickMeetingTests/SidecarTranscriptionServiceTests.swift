import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct SidecarTranscriptionServiceTests {
    @Test
    func transcribeCompletedEventPersistsTranscriptAndCompletesMeeting() async throws {
        let harness = try SidecarTranscriptionHarness()
        let meeting = try harness.createRecordedMeeting()
        await harness.launcher.setResult(.success([
            #"{"status":"running"}"#,
            #"{"status":"transcribing","percent":40}"#,
            #"{"status":"diarization","step":"segmentation","percent":100}"#,
            #"{"status":"completed","speakers":[{"id":"SPEAKER_00","matched_id":null,"probability":null,"centroid":null}],"segments":[{"speaker":"SPEAKER_00","start":0.0,"end":1.5,"text":"Hello"}]}"#,
        ]))

        try await harness.service.transcribe(meetingID: meeting.id)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .completed)
        #expect(reloaded.transcriptPreview == "Hello")
        #expect(reloaded.transcriptSpeakers.map(\.displayName) == ["Speaker 1"])
        #expect(reloaded.transcriptSegments.map(\.speakerID) == ["SPEAKER_00"])
        #expect(harness.progressCenter.progress(for: meeting.id) == nil)
        #expect(harness.progressCenter.diarizationProgress(for: meeting.id) == nil)
    }

    @Test
    func transcribeErrorEventMarksMeetingFailed() async throws {
        let harness = try SidecarTranscriptionHarness()
        let meeting = try harness.createRecordedMeeting()
        await harness.launcher.setResult(.failure(.sidecarReported("ffmpeg failed")))

        await #expect(throws: SidecarTranscriptionServiceError.sidecarFailed("ffmpeg failed")) {
            try await harness.service.transcribe(meetingID: meeting.id)
        }

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .failed)
    }

    @Test
    func transcribeRejectsSecondJobWhileFirstIsActive() async throws {
        let harness = try SidecarTranscriptionHarness()
        let firstMeeting = try harness.createRecordedMeeting()
        let secondMeeting = try harness.createRecordedMeeting()
        await harness.launcher.suspendNextRun()

        let task = Task {
            try await harness.service.transcribe(meetingID: firstMeeting.id)
        }

        await harness.launcher.waitForSuspendedRun()

        await #expect(throws: TranscriptionServiceError.transcriptionAlreadyActive) {
            try await harness.service.transcribe(meetingID: secondMeeting.id)
        }

        await harness.launcher.resume(with: .success([
            #"{"status":"completed","speakers":[],"segments":[]}"#,
        ]))
        try await task.value
    }

    @Test
    func transcribePassesExecutableArgumentsAndHFHomeToLauncher() async throws {
        let harness = try SidecarTranscriptionHarness()
        let meeting = try harness.createRecordedMeeting()
        let executableURL = URL(fileURLWithPath: "/tmp/QuickMeetingSidecar/example")
        let hfHomeURL = URL(fileURLWithPath: "/tmp/Application Support/QuickMeeting/HuggingFace")
        harness.runtimeConfiguration.executableURL = executableURL
        harness.runtimeConfiguration.hfHomeURL = hfHomeURL
        await harness.launcher.setResult(.success([
            #"{"status":"completed","speakers":[],"segments":[]}"#,
        ]))

        try await harness.service.transcribe(meetingID: meeting.id)

        let request = try await #require(harness.launcher.requests.first)
        #expect(request.executableURL == executableURL)
        #expect(request.arguments == ["--input-file", meeting.audioFilePath, "--hf-token", "hardcoded-token"])
        #expect(request.environment["HF_HOME"] == hfHomeURL.path)
    }

    @Test
    func transcribeIgnoresMalformedLinesWhenCompletedEventArrivesLater() async throws {
        let harness = try SidecarTranscriptionHarness()
        let meeting = try harness.createRecordedMeeting()
        await harness.launcher.setResult(.success([
            "warning: not json",
            #"{"status":"completed","speakers":[],"segments":[]}"#,
        ]))

        try await harness.service.transcribe(meetingID: meeting.id)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .completed)
    }

    @Test
    func defaultLauncherThrowsExecutableMissingForAbsentBinary() async throws {
        let launcher = DefaultSidecarProcessLauncher()

        await #expect(throws: SidecarLaunchError.executableMissing) {
            try await launcher.run(
                SidecarLaunchRequest(
                    executableURL: URL(fileURLWithPath: "/tmp/does-not-exist/example"),
                    arguments: [],
                    environment: [:]
                ),
                onLine: { _ in }
            )
        }
    }
}

@MainActor
private struct SidecarTranscriptionHarness {
    let container: ModelContainer
    let context: ModelContext
    let meetingStore: MeetingStore
    let progressCenter: TranscriptionProgressCenter
    let fileManager: FileManager
    let meetingFileStore: MeetingFileStore
    let runtimeConfiguration: SidecarHarnessRuntimeConfiguration
    let launcher: SuspendedSidecarProcessLauncher
    let service: SidecarTranscriptionService

    init() throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        context = ModelContext(container)
        meetingStore = MeetingStore(modelContext: context)
        progressCenter = TranscriptionProgressCenter()
        fileManager = .default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        meetingFileStore = MeetingFileStore(fileManager: fileManager, rootURL: rootURL)
        let runtimeConfiguration = SidecarHarnessRuntimeConfiguration()
        self.runtimeConfiguration = runtimeConfiguration
        launcher = SuspendedSidecarProcessLauncher()
        service = SidecarTranscriptionService(
            meetingStore: meetingStore,
            progressCenter: progressCenter,
            launcher: launcher,
            executableURLProvider: { runtimeConfiguration.executableURL },
            hfTokenProvider: { "hardcoded-token" },
            hfHomeURLProvider: { runtimeConfiguration.hfHomeURL },
            fileManager: fileManager,
            dateProvider: Date.init
        )
    }

    func createRecordedMeeting() throws -> Meeting {
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let artifacts = try meetingFileStore.createArtifacts(for: UUID(), startedAt: startedAt)
        fileManager.createFile(atPath: artifacts.audioFileURL.path, contents: Data("audio".utf8))
        let meeting = try meetingStore.createMeeting(
            id: UUID(uuidString: artifacts.meetingFolderURL.lastPathComponent) ?? UUID(),
            title: "Design Review",
            startedAt: startedAt,
            folderURL: artifacts.meetingFolderURL,
            audioFileURL: artifacts.audioFileURL
        )
        try meetingStore.finishRecording(meetingID: meeting.id, endedAt: startedAt.addingTimeInterval(60))
        return try reloadMeeting(id: meeting.id)
    }

    func reloadMeeting(id: UUID) throws -> Meeting {
        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { meeting in
                meeting.id == id
            }
        )
        return try #require(verificationContext.fetch(descriptor).first)
    }
}

private actor SuspendedSidecarProcessLauncher: SidecarProcessLaunching {
    private(set) var requests = [SidecarLaunchRequest]()
    private var result: Result<[String], SidecarLaunchError> = .success([])
    private var shouldSuspendNextRun = false
    private var pendingRunCount = 0
    private var pendingContinuation: CheckedContinuation<Result<[String], SidecarLaunchError>, Never>?

    func setResult(_ result: Result<[String], SidecarLaunchError>) {
        self.result = result
    }

    func suspendNextRun() {
        shouldSuspendNextRun = true
    }

    func waitForSuspendedRun() async {
        while pendingRunCount == 0 {
            await Task.yield()
        }
    }

    func resume(with result: Result<[String], SidecarLaunchError>) {
        pendingRunCount = max(0, pendingRunCount - 1)
        pendingContinuation?.resume(returning: result)
        pendingContinuation = nil
    }

    func run(
        _ request: SidecarLaunchRequest,
        onLine: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        requests.append(request)
        let resolvedResult: Result<[String], SidecarLaunchError>
        if shouldSuspendNextRun {
            shouldSuspendNextRun = false
            pendingRunCount += 1
            resolvedResult = await withCheckedContinuation { continuation in
                pendingContinuation = continuation
            }
        } else {
            resolvedResult = result
        }

        for line in try resolvedResult.get() {
            try await onLine(line)
        }
    }
}

private final class SidecarHarnessRuntimeConfiguration: @unchecked Sendable {
    var executableURL = URL(fileURLWithPath: "/tmp/example/example")
    var hfHomeURL = URL(fileURLWithPath: "/tmp/HuggingFace")
}
