import AVFoundation
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
            #"{"status":"diarization","step":"embeddings","percent":25}"#,
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
    func transcribeRejectsMissingHuggingFaceTokenBeforeLaunchingSidecar() async throws {
        let harness = try SidecarTranscriptionHarness(hfToken: "  ")
        let meeting = try harness.createRecordedMeeting()

        await #expect(throws: TranscriptionServiceError.missingHuggingFaceToken) {
            try await harness.service.transcribe(meetingID: meeting.id)
        }

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .recorded)
        let requests = await harness.launcher.requests
        #expect(requests.isEmpty)
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
    func transcribePassesPythonInterpreterWorkingDirectoryAndScriptArguments() async throws {
        let harness = try SidecarTranscriptionHarness()
        let meeting = try harness.createRecordedMeeting()
        let executableURL = URL(fileURLWithPath: "/tmp/QuickMeetingSidecar/python/lib/bin/python")
        let workingDirectoryURL = URL(fileURLWithPath: "/tmp/QuickMeetingSidecar/python", isDirectory: true)
        let hfHomeURL = URL(fileURLWithPath: "/tmp/Application Support/QuickMeeting/HuggingFace")
        let wavURL = URL(fileURLWithPath: meeting.audioFilePath).deletingPathExtension().appendingPathExtension("wav")
        harness.runtimeConfiguration.executableURL = executableURL
        harness.runtimeConfiguration.workingDirectoryURL = workingDirectoryURL
        harness.runtimeConfiguration.hfHomeURL = hfHomeURL
        await harness.audioPreparer.setPreparedAudioURL(wavURL)
        await harness.launcher.setResult(.success([
            #"{"status":"completed","speakers":[],"segments":[]}"#,
        ]))

        try await harness.service.transcribe(meetingID: meeting.id)

        let request = try await #require(harness.launcher.requests.first)
        #expect(request.executableURL == executableURL)
        #expect(request.workingDirectoryURL == workingDirectoryURL)
        #expect(request.arguments == [
            "main.py",
            "--input-file",
            wavURL.path,
            "--hf-token",
            "hardcoded-token",
        ])
        #expect(request.environment["HF_HOME"] == hfHomeURL.path)
    }

    @Test
    func transcribePassesOptionalLanguageAndInitialPromptArguments() async throws {
        let harness = try SidecarTranscriptionHarness(
            transcriptionLanguage: .russian,
            initialPrompt: "Alice, Bob, Kubernetes"
        )
        let meeting = try harness.createRecordedMeeting()
        let wavURL = URL(fileURLWithPath: meeting.audioFilePath).deletingPathExtension().appendingPathExtension("wav")
        await harness.audioPreparer.setPreparedAudioURL(wavURL)
        await harness.launcher.setResult(.success([
            #"{"status":"completed","speakers":[],"segments":[]}"#,
        ]))

        try await harness.service.transcribe(meetingID: meeting.id)

        let request = try await #require(harness.launcher.requests.first)
        #expect(request.arguments == [
            "main.py",
            "--input-file",
            wavURL.path,
            "--hf-token",
            "hardcoded-token",
            "--language",
            "ru",
            "--initial-prompt",
            "Alice, Bob, Kubernetes",
        ])
    }

    @Test
    func transcribePassesKnownSpeakersFileWhenStoreHasCentroids() async throws {
        let harness = try SidecarTranscriptionHarness()
        let meeting = try harness.createRecordedMeeting()
        try harness.knownSpeakerStore.findOrCreateSpeaker(named: "Alice", now: .now)
        try harness.knownSpeakerStore.appendCentroid(
            [0.1, 0.2],
            to: try harness.firstKnownSpeakerID(),
            sourceMeetingID: nil,
            sourceSpeakerID: nil,
            now: .now
        )
        await harness.launcher.setResult(.success([
            #"{"status":"completed","speakers":[],"segments":[]}"#,
        ]))

        try await harness.service.transcribe(meetingID: meeting.id)

        let request = try await #require(harness.launcher.requests.first)
        #expect(request.arguments.contains("--known-speakers-file"))
    }

    @Test
    func transcribePersistsBankMatchedSpeakerMetadata() async throws {
        let harness = try SidecarTranscriptionHarness()
        let meeting = try harness.createRecordedMeeting()
        try harness.insertKnownSpeaker(
            id: "known-alice",
            displayName: "Alice",
            centroids: [[0.9, 0.8]]
        )
        await harness.launcher.setResult(.success([
            #"{"status":"completed","speakers":[{"id":"SPEAKER_00","matched_id":"known-alice","probability":0.91,"centroid":[0.1,0.2]}],"segments":[{"speaker":"SPEAKER_00","start":0.0,"end":1.5,"text":"Hello"}]}"#,
        ]))

        try await harness.service.transcribe(meetingID: meeting.id)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        let speaker = try #require(reloaded.storedTranscript?.speakers.first)
        #expect(speaker.displayName == "Alice")
        #expect(speaker.labelSource == .bankMatched)
        #expect(speaker.matchedKnownSpeakerID == "known-alice")
        #expect(speaker.centroid == [0.1, 0.2])
    }

    @Test
    func transcribePersistsTranscriptEvenWhenEnrollmentFailsForBankMatchedSpeaker() async throws {
        let harness = try SidecarTranscriptionHarness(
            enrollmentResult: .failure(SidecarTestError.failed)
        )
        let meeting = try harness.createRecordedMeeting()
        try harness.insertKnownSpeaker(
            id: "known-alice",
            displayName: "Alice",
            centroids: [[0.9, 0.8]]
        )
        await harness.launcher.setResult(.success([
            #"{"status":"completed","speakers":[{"id":"SPEAKER_00","matched_id":"known-alice","probability":0.91,"centroid":[0.1,0.2]}],"segments":[{"speaker":"SPEAKER_00","start":0.0,"end":1.5,"text":"Hello"}]}"#,
        ]))

        try await harness.service.transcribe(meetingID: meeting.id)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .completed)
        #expect(await harness.enrollmentService.calls.count == 1)
    }

    @Test
    func transcribeOmitsOptionalLanguageAndInitialPromptArgumentsWhenUnset() async throws {
        let harness = try SidecarTranscriptionHarness(
            transcriptionLanguage: .none,
            initialPrompt: "   "
        )
        let meeting = try harness.createRecordedMeeting()
        let wavURL = URL(fileURLWithPath: meeting.audioFilePath).deletingPathExtension().appendingPathExtension("wav")
        await harness.audioPreparer.setPreparedAudioURL(wavURL)
        await harness.launcher.setResult(.success([
            #"{"status":"completed","speakers":[],"segments":[]}"#,
        ]))

        try await harness.service.transcribe(meetingID: meeting.id)

        let request = try await #require(harness.launcher.requests.first)
        #expect(request.arguments == [
            "main.py",
            "--input-file",
            wavURL.path,
            "--hf-token",
            "hardcoded-token",
        ])
    }

    @Test
    func transcribeDeletesPreparedWAVAfterSuccess() async throws {
        let harness = try SidecarTranscriptionHarness()
        let meeting = try harness.createRecordedMeeting()
        let wavURL = URL(fileURLWithPath: meeting.audioFilePath).deletingPathExtension().appendingPathExtension("wav")
        harness.fileManager.createFile(atPath: wavURL.path, contents: Data("wav".utf8))
        await harness.audioPreparer.setPreparedAudioURL(wavURL)
        await harness.launcher.setResult(.success([
            #"{"status":"completed","speakers":[],"segments":[]}"#,
        ]))

        try await harness.service.transcribe(meetingID: meeting.id)

        let preparedSourceURL = await harness.audioPreparer.preparedSourceURL
        #expect(preparedSourceURL?.path == meeting.audioFilePath)
        #expect(!harness.fileManager.fileExists(atPath: wavURL.path))
    }

    @Test
    func transcribeDeletesPreparedWAVAfterFailure() async throws {
        let harness = try SidecarTranscriptionHarness()
        let meeting = try harness.createRecordedMeeting()
        let wavURL = URL(fileURLWithPath: meeting.audioFilePath).deletingPathExtension().appendingPathExtension("wav")
        harness.fileManager.createFile(atPath: wavURL.path, contents: Data("wav".utf8))
        await harness.audioPreparer.setPreparedAudioURL(wavURL)
        await harness.launcher.setResult(.failure(.sidecarReported("python failed")))

        await #expect(throws: SidecarTranscriptionServiceError.sidecarFailed("python failed")) {
            try await harness.service.transcribe(meetingID: meeting.id)
        }

        #expect(!harness.fileManager.fileExists(atPath: wavURL.path))
    }

    @Test
    func defaultAudioPreparerUsesExistingWAVAndCleanupRemovesIt() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceURL = rootURL.appendingPathComponent("audio.m4a")
        fileManager.createFile(atPath: sourceURL.path, contents: Data("m4a".utf8))
        let existingWAVURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: existingWAVURL.path, contents: Data("wav".utf8))
        let preparer = DefaultSidecarTranscriptionAudioPreparer(fileManager: fileManager)

        let preparedAudio = try await preparer.prepareAudioFile(for: sourceURL)

        #expect(preparedAudio.fileURL == existingWAVURL)
        #expect(fileManager.fileExists(atPath: preparedAudio.fileURL.path))

        preparedAudio.cleanup()

        #expect(!fileManager.fileExists(atPath: preparedAudio.fileURL.path))
    }

    @Test
    func defaultAudioPreparerConvertsRecordedM4AToNonEmptyWAV() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sourceURL = rootURL.appendingPathComponent("audio.m4a")
        try createRecordedM4ATestFile(at: sourceURL)
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        #expect(sourceFile.length > 0)
        let preparer = DefaultSidecarTranscriptionAudioPreparer(fileManager: fileManager)

        let preparedAudio: PreparedSidecarTranscriptionAudio
        do {
            preparedAudio = try await preparer.prepareAudioFile(for: sourceURL)
        } catch {
            throw TestFailure("prepareAudioFile threw: \(String(describing: error))")
        }

        #expect(fileManager.fileExists(atPath: preparedAudio.fileURL.path))
        let fileSize = try fileSize(at: preparedAudio.fileURL, fileManager: fileManager)
        #expect(fileSize > 44, "Expected converted WAV to contain audio data, size was \(fileSize) bytes")
        let wavFile = try AVAudioFile(forReading: preparedAudio.fileURL)
        #expect(wavFile.length > 0)
        #expect(wavFile.processingFormat.sampleRate == 16_000)
        #expect(wavFile.processingFormat.channelCount == 1)

        preparedAudio.cleanup()
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
    func defaultExecutableURLResolvesBundledPythonInterpreter() throws {
        let fileManager = FileManager.default
        let bundleURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let bundledInterpreterURL = resourcesURL
            .appendingPathComponent("python", isDirectory: true)
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python", isDirectory: false)
        try fileManager.createDirectory(at: bundledInterpreterURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: bundledInterpreterURL.path, contents: Data())
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.example.QuickMeetingTests</string>
            <key>CFBundleName</key>
            <string>QuickMeetingTests</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
        </dict>
        </plist>
        """.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let bundle = try #require(Bundle(url: bundleURL))

        let resolvedURL = try #require(SidecarTranscriptionService.defaultExecutableURL(bundle: bundle))

        #expect(resolvedURL.path == bundledInterpreterURL.path)
    }

    @Test
    func defaultExecutableURLFallsBackToVirtualenvInterpreter() throws {
        let fileManager = FileManager.default
        let bundleURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let fallbackInterpreterURL = resourcesURL
            .appendingPathComponent("python", isDirectory: true)
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python", isDirectory: false)
        try fileManager.createDirectory(
            at: fallbackInterpreterURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        fileManager.createFile(atPath: fallbackInterpreterURL.path, contents: Data())
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.example.QuickMeetingTests</string>
            <key>CFBundleName</key>
            <string>QuickMeetingTests</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
        </dict>
        </plist>
        """.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let bundle = try #require(Bundle(url: bundleURL))

        let resolvedURL = try #require(SidecarTranscriptionService.defaultExecutableURL(bundle: bundle))

        #expect(resolvedURL.path == fallbackInterpreterURL.path)
    }

    @Test
    func defaultLauncherThrowsExecutableMissingForAbsentBinary() async throws {
        let launcher = DefaultSidecarProcessLauncher()

        await #expect(throws: SidecarLaunchError.executableMissing) {
            try await launcher.run(
                SidecarLaunchRequest(
                    executableURL: URL(fileURLWithPath: "/tmp/does-not-exist/example"),
                    workingDirectoryURL: URL(fileURLWithPath: "/tmp/does-not-exist", isDirectory: true),
                    arguments: [],
                    environment: [:]
                ),
                onLine: { _ in }
            )
        }
    }

    @Test
    func defaultLauncherDeliversStdoutLinesBeforeProcessExits() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let scriptURL = rootURL.appendingPathComponent("streaming-sidecar.sh")
        try """
        #!/bin/sh
        printf '%s\\n' '{"status":"running"}'
        sleep 1
        printf '%s\\n' '{"status":"completed","speakers":[],"segments":[]}'
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let launcher = DefaultSidecarProcessLauncher()
        let firstLine = AsyncStream<String>.makeStream()
        var deliveredLines = [String]()

        let runTask = Task {
            try await launcher.run(
                SidecarLaunchRequest(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    workingDirectoryURL: rootURL,
                    arguments: [scriptURL.path],
                    environment: [:]
                )
            ) { line in
                deliveredLines.append(line)
                if deliveredLines.count == 1 {
                    firstLine.continuation.yield(line)
                    firstLine.continuation.finish()
                }
            }
        }

        var iterator = firstLine.stream.makeAsyncIterator()
        let observedFirstLine = await iterator.next()

        #expect(observedFirstLine == #"{"status":"running"}"#)
        #expect(!runTask.isCancelled)

        try await runTask.value
        #expect(deliveredLines == [
            #"{"status":"running"}"#,
            #"{"status":"completed","speakers":[],"segments":[]}"#,
        ])
    }

    @Test
    func defaultLauncherDrainsStderrWhileProcessRuns() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let scriptURL = rootURL.appendingPathComponent("stderr-heavy-sidecar.sh")
        try """
        #!/bin/sh
        i=0
        while [ "$i" -lt 20000 ]; do
          printf 'diagnostic line %s\\n' "$i" >&2
          i=$((i + 1))
        done
        printf '%s\\n' '{"status":"completed","speakers":[],"segments":[]}'
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var lines = [String]()
        try await DefaultSidecarProcessLauncher().run(
            SidecarLaunchRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                workingDirectoryURL: rootURL,
                arguments: [scriptURL.path],
                environment: [:]
            )
        ) { line in
            lines.append(line)
        }

        #expect(lines == [#"{"status":"completed","speakers":[],"segments":[]}"#])
    }
}

@MainActor
private struct SidecarTranscriptionHarness {
    let container: ModelContainer
    let context: ModelContext
    let meetingStore: MeetingStore
    let knownSpeakerStore: KnownSpeakerStore
    let progressCenter: TranscriptionProgressCenter
    let fileManager: FileManager
    let meetingFileStore: MeetingFileStore
    let runtimeConfiguration: SidecarHarnessRuntimeConfiguration
    let launcher: SuspendedSidecarProcessLauncher
    let audioPreparer: StubSidecarTranscriptionAudioPreparer
    let enrollmentService: StubKnownSpeakerEnrollmentService
    let service: SidecarTranscriptionService

    init(
        hfToken: String = "hardcoded-token",
        transcriptionLanguage: TranscriptionLanguage = .none,
        initialPrompt: String = "",
        enrollmentResult: Result<Void, Error> = .success(())
    ) throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        context = ModelContext(container)
        meetingStore = MeetingStore(modelContext: context)
        knownSpeakerStore = KnownSpeakerStore(modelContext: context)
        progressCenter = TranscriptionProgressCenter()
        fileManager = .default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        meetingFileStore = MeetingFileStore(fileManager: fileManager, rootURL: rootURL)
        let runtimeConfiguration = SidecarHarnessRuntimeConfiguration()
        self.runtimeConfiguration = runtimeConfiguration
        launcher = SuspendedSidecarProcessLauncher()
        audioPreparer = StubSidecarTranscriptionAudioPreparer(fileManager: fileManager)
        enrollmentService = StubKnownSpeakerEnrollmentService(result: enrollmentResult)
        service = SidecarTranscriptionService(
            meetingStore: meetingStore,
            progressCenter: progressCenter,
            launcher: launcher,
            executableURLProvider: { runtimeConfiguration.executableURL },
            hfTokenProvider: { hfToken },
            transcriptionLanguageProvider: { transcriptionLanguage },
            initialPromptProvider: { initialPrompt },
            hfHomeURLProvider: { runtimeConfiguration.hfHomeURL },
            knownSpeakerStore: knownSpeakerStore,
            knownSpeakerEnrollmentService: enrollmentService,
            audioPreparer: audioPreparer,
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

    func firstKnownSpeakerID() throws -> String {
        try #require(knownSpeakerStore.allSpeakers().first?.id)
    }

    func insertKnownSpeaker(id: String, displayName: String, centroids: [[Double]]) throws {
        let speaker = PersistedKnownSpeaker(
            id: id,
            displayName: displayName,
            createdAt: .now,
            updatedAt: .now
        )
        speaker.centroids = centroids.enumerated().map { index, values in
            PersistedKnownSpeakerCentroid(
                values: values,
                sourceMeetingID: nil,
                sourceSpeakerID: nil,
                createdAt: Date(timeIntervalSince1970: Double(index + 1))
            )
        }
        context.insert(speaker)
        try context.save()
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

private actor StubKnownSpeakerEnrollmentService: KnownSpeakerEnrolling {
    struct Call: Sendable {
        let displayName: String
        let speaker: TranscriptSpeaker
        let meetingID: UUID
    }

    private(set) var calls = [Call]()
    private let result: Result<Void, Error>

    init(result: Result<Void, Error>) {
        self.result = result
    }

    func enroll(displayName: String, speaker: TranscriptSpeaker, meetingID: UUID) async throws {
        calls.append(Call(displayName: displayName, speaker: speaker, meetingID: meetingID))
        try result.get()
    }
}

private enum SidecarTestError: Error {
    case failed
}

private final class SidecarHarnessRuntimeConfiguration: @unchecked Sendable {
    var executableURL = URL(fileURLWithPath: "/tmp/example/python/lib/bin/python")
    var workingDirectoryURL = URL(fileURLWithPath: "/tmp/example/python", isDirectory: true)
    var hfHomeURL = URL(fileURLWithPath: "/tmp/HuggingFace")
}

private actor StubSidecarTranscriptionAudioPreparer: SidecarTranscriptionAudioPreparing {
    private let fileManager: FileManager
    private(set) var preparedSourceURL: URL?
    private var preparedAudioURL: URL?

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func setPreparedAudioURL(_ url: URL) {
        preparedAudioURL = url
    }

    func prepareAudioFile(for sourceURL: URL) async throws -> PreparedSidecarTranscriptionAudio {
        preparedSourceURL = sourceURL
        let targetURL = preparedAudioURL ?? sourceURL.deletingPathExtension().appendingPathExtension("wav")
        if !fileManager.fileExists(atPath: targetURL.path) {
            fileManager.createFile(atPath: targetURL.path, contents: Data("wav".utf8))
        }

        return PreparedSidecarTranscriptionAudio(fileURL: targetURL) {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: targetURL.path) else {
                return
            }

            try? fileManager.removeItem(at: targetURL)
        }
    }
}

private func createRecordedM4ATestFile(at url: URL) throws {
    let writer = try AACM4AAudioFileWriter(outputURL: url)
    let format = CanonicalAudioBufferConverter.canonicalFormat
    let frameCount: AVAudioFrameCount = 48_000
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount
    let channels = try #require(buffer.floatChannelData)
    let sampleRate = Float(format.sampleRate)

    for channelIndex in 0 ..< Int(format.channelCount) {
        let channel = channels[channelIndex]
        for frameIndex in 0 ..< Int(frameCount) {
            let sample = sin((2 * Float.pi * 220 * Float(frameIndex)) / sampleRate)
            channel[frameIndex] = channelIndex == 0 ? sample : sample * 0.5
        }
    }

    try writer.append(buffer)
    try writer.finish()
}

private func fileSize(at url: URL, fileManager: FileManager) throws -> UInt64 {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    guard let size = attributes[.size] as? NSNumber else {
        throw TestFailure("Could not read file size for \(url.path)")
    }

    return size.uint64Value
}

private struct TestFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
