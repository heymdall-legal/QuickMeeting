import Foundation
import CoreMedia
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct AppViewModelTests {
    @Test
    func startRecordingTransitionsFromIdleToRecording() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            dateProvider: { startedAt },
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        #expect(viewModel.recordingState == .idle)

        await viewModel.startRecording()

        #expect(viewModel.recordingState == .recording(meetingID: meetingID))

        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.count == 1)

        let persistedMeeting = try #require(persistedMeetings.first)
        #expect(persistedMeeting.id == meetingID)
        #expect(persistedMeeting.startedAt == startedAt)
        #expect(
            persistedMeeting.audioFilePath
                == harness.artifactsURL(for: meetingID).audioFileURL
                .standardizedFileURL
                .path()
        )

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 1)
        #expect(snapshot.startAttempts.first?.meetingID == meetingID)
        #expect(snapshot.startAttempts.first?.outputURL == harness.artifactsURL(for: meetingID).audioFileURL)
    }

    @Test
    func startRecordingFailureRollsBackPersistedMeetingAndArtifacts() async throws {
        let harness = try AppViewModelTestHarness(
            queuedResults: [.failure(StartRecordingTestError.startFailed)]
        )
        let meetingID = UUID()
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        await viewModel.startRecording()

        #expect(viewModel.recordingState == .failed(message: "Recording startup failed"))
        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.isEmpty)
        #expect(!harness.fileManager.fileExists(atPath: harness.artifactsURL(for: meetingID).meetingFolderURL.path))

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 1)
        #expect(snapshot.stopAttempts == 1)
        #expect(snapshot.startAttempts.first?.meetingID == meetingID)
    }

    @Test
    func startRecordingAllowsRetryFromFailedState() async throws {
        let harness = try AppViewModelTestHarness(
            queuedResults: [
                .failure(StartRecordingTestError.startFailed),
                .success(())
            ]
        )
        let firstMeetingID = UUID()
        let secondMeetingID = UUID()
        var meetingIDs = [firstMeetingID, secondMeetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        await viewModel.startRecording()
        #expect(viewModel.recordingState == .failed(message: "Recording startup failed"))

        await viewModel.startRecording()

        #expect(viewModel.recordingState == .recording(meetingID: secondMeetingID))
        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.count == 1)
        #expect(persistedMeetings.first?.id == secondMeetingID)
        #expect(!harness.fileManager.fileExists(atPath: harness.artifactsURL(for: firstMeetingID).meetingFolderURL.path))
        #expect(harness.fileManager.fileExists(atPath: harness.artifactsURL(for: secondMeetingID).meetingFolderURL.path))

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 2)
        #expect(snapshot.startAttempts.map(\.meetingID) == [firstMeetingID, secondMeetingID])
    }

    @Test
    func startRecordingFailsEarlyWhenPermissionsAreDenied() async throws {
        let harness = try AppViewModelTestHarness(
            permissionResult: .denied(message: "Screen recording permission is required.")
        )
        let meetingID = UUID()
        var meetingIDWasRequested = false
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            meetingIDProvider: {
                meetingIDWasRequested = true
                return meetingIDs.removeFirst()
            }
        )

        await viewModel.startRecording()

        #expect(viewModel.recordingState == .failed(message: "Screen recording permission is required."))
        #expect(harness.recordingPermissions.snapshot().ensurePermissionsCallCount == 1)
        #expect(harness.recordingService.snapshot().startAttempts.isEmpty)
        #expect(!meetingIDWasRequested)

        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.isEmpty)
        #expect(!harness.fileManager.fileExists(atPath: harness.artifactsURL(for: meetingID).meetingFolderURL.path))
    }

    @Test
    func startRecordingSerializesWhileWaitingForPermissions() async throws {
        let harness = try AppViewModelTestHarness()
        let permissionSpy = SuspendedRecordingPermissionsSpy()
        let meetingID = UUID()
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: permissionSpy,
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        let firstStart = Task { @MainActor in
            await viewModel.startRecording()
        }

        while permissionSpy.ensurePermissionsCallCount == 0 {
            await Task.yield()
        }

        await viewModel.startRecording()

        #expect(viewModel.recordingState == .starting)
        #expect(harness.recordingService.snapshot().startAttempts.isEmpty)

        permissionSpy.resume(with: .granted)
        await firstStart.value

        #expect(viewModel.recordingState == .recording(meetingID: meetingID))
        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.count == 1)

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 1)
        #expect(snapshot.startAttempts.first?.meetingID == meetingID)
    }

    @Test
    func stopRecordingTransitionsToIdleAndFinishesMeeting() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let endedAt = startedAt.addingTimeInterval(95)
        var capturedDates = [startedAt, endedAt]
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            dateProvider: { capturedDates.removeFirst() },
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        #expect(viewModel.canStartRecording)
        #expect(!viewModel.canStopRecording)

        await viewModel.startRecording()

        #expect(!viewModel.canStartRecording)
        #expect(viewModel.canStopRecording)

        await viewModel.stopRecording()

        #expect(viewModel.recordingState == .idle)
        #expect(viewModel.canStartRecording)
        #expect(!viewModel.canStopRecording)

        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.count == 1)

        let persistedMeeting = try #require(persistedMeetings.first)
        #expect(persistedMeeting.id == meetingID)
        #expect(persistedMeeting.endedAt == endedAt)
        #expect(persistedMeeting.duration == 95)
        #expect(try persistedMeeting.status == .recorded)

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 1)
        #expect(snapshot.stopAttempts == 1)
    }

    @Test
    func stopRecordingFailureKeepsRecoverableMeetingAvailableToTheUI() async throws {
        let harness = try AppViewModelTestHarness(
            stopResults: [.failure(StopRecordingTestError.stopFailed)]
        )
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            dateProvider: { startedAt },
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        await viewModel.startRecording()
        await viewModel.stopRecording()

        #expect(viewModel.recordingState == .failed(message: "Recording shutdown failed"))
        #expect(viewModel.activeOrRecoverableMeetingID == meetingID)
        #expect(!viewModel.canStartRecording)
        #expect(viewModel.canStopRecording)

        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        let persistedMeeting = try #require(persistedMeetings.first)
        #expect(try persistedMeeting.status == .recording)
        #expect(persistedMeeting.endedAt == nil)

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 1)
        #expect(snapshot.stopAttempts == 1)
    }
}

@MainActor
struct MenuBarViewTests {
    @Test
    func primaryActionTitleTracksSharedRecordingState() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            meetingIDProvider: { meetingIDs.removeFirst() }
        )
        let view = MenuBarView(viewModel: viewModel)

        #expect(view.primaryActionTitle == "Start Recording")

        await view.performPrimaryAction()
        #expect(viewModel.recordingState == .recording(meetingID: meetingID))
        #expect(view.primaryActionTitle == "Stop Recording")

        await view.performPrimaryAction()
        #expect(viewModel.recordingState == .idle)
        #expect(view.primaryActionTitle == "Start Recording")
    }
}

@MainActor
struct DefaultRecordingServiceTests {
    @Test
    func startRecordingThrowsWhenARecordingIsAlreadyActive() async throws {
        let pipeline = AudioCapturePipelineSpy()
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)

        try await service.startRecording(
            meeting: makeMeeting(),
            outputURL: URL(fileURLWithPath: "/tmp/first-audio.wav")
        )

        await #expect(throws: DefaultRecordingServiceError.recordingAlreadyActive) {
            try await service.startRecording(
                meeting: makeMeeting(),
                outputURL: URL(fileURLWithPath: "/tmp/second-audio.wav")
            )
        }

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.startedOutputURLs == [URL(fileURLWithPath: "/tmp/first-audio.wav")])
    }

    @Test
    func stopRecordingStopsThePipelineAndClearsTheActiveRecording() async throws {
        let pipeline = AudioCapturePipelineSpy()
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)
        let firstOutputURL = URL(fileURLWithPath: "/tmp/first-audio.wav")
        let secondOutputURL = URL(fileURLWithPath: "/tmp/second-audio.wav")

        try await service.startRecording(meeting: makeMeeting(), outputURL: firstOutputURL)
        try await service.stopRecording()
        try await service.startRecording(meeting: makeMeeting(), outputURL: secondOutputURL)

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.startedOutputURLs == [firstOutputURL, secondOutputURL])
        #expect(snapshot.stopCallCount == 1)
    }

    @Test
    func startRecordingReturnsToIdleWhenPipelineStartThrows() async throws {
        let pipeline = AudioCapturePipelineSpy(
            startResults: [
                .failure(AudioCapturePipelineTestError.startFailed),
                .success(())
            ]
        )
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)
        let firstOutputURL = URL(fileURLWithPath: "/tmp/failed-audio.wav")
        let secondOutputURL = URL(fileURLWithPath: "/tmp/retry-audio.wav")

        await #expect(throws: AudioCapturePipelineTestError.startFailed) {
            try await service.startRecording(meeting: makeMeeting(), outputURL: firstOutputURL)
        }

        try await service.startRecording(meeting: makeMeeting(), outputURL: secondOutputURL)

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.startedOutputURLs == [firstOutputURL, secondOutputURL])
        #expect(snapshot.stopCallCount == 0)
    }

    @Test
    func stopRecordingCanBeRetriedWhenPipelineStopThrows() async throws {
        let pipeline = AudioCapturePipelineSpy(
            stopResults: [
                .failure(AudioCapturePipelineTestError.stopFailed),
                .success(())
            ]
        )
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)

        try await service.startRecording(
            meeting: makeMeeting(),
            outputURL: URL(fileURLWithPath: "/tmp/first-audio.wav")
        )

        await #expect(throws: AudioCapturePipelineTestError.stopFailed) {
            try await service.stopRecording()
        }

        await #expect(throws: DefaultRecordingServiceError.recordingAlreadyActive) {
            try await service.startRecording(
                meeting: makeMeeting(),
                outputURL: URL(fileURLWithPath: "/tmp/second-audio.wav")
            )
        }

        try await service.stopRecording()
        try await service.startRecording(
            meeting: makeMeeting(),
            outputURL: URL(fileURLWithPath: "/tmp/second-audio.wav")
        )

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.stopCallCount == 2)
    }

    @Test
    func stopRecordingDuringSuspendedStartWaitsForStartToFinishBeforeStopping() async throws {
        let pipeline = AudioCapturePipelineSpy(suspendNextStart: true)
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)
        let firstOutputURL = URL(fileURLWithPath: "/tmp/first-audio.wav")
        let secondOutputURL = URL(fileURLWithPath: "/tmp/second-audio.wav")

        let startTask = Task { @MainActor in
            try await service.startRecording(meeting: makeMeeting(), outputURL: firstOutputURL)
        }

        while await pipeline.snapshot().pendingStartCount == 0 {
            await Task.yield()
        }

        let stopTask = Task { @MainActor in
            try await service.stopRecording()
        }
        let duplicateStopTask = Task { @MainActor in
            try await service.stopRecording()
        }

        #expect(await pipeline.snapshot().stopCallCount == 0)

        await pipeline.resumeStart(with: .success(()))
        try await startTask.value
        try await stopTask.value
        try await duplicateStopTask.value

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.startCallCount == 1)
        #expect(snapshot.stopCallCount == 1)
        #expect(snapshot.startedOutputURLs == [firstOutputURL])

        try await service.startRecording(meeting: makeMeeting(), outputURL: secondOutputURL)
    }

    @Test
    func duplicateStopCallsShareTheSameSuspendedStopOperation() async throws {
        let pipeline = AudioCapturePipelineSpy(suspendNextStop: true)
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)
        let firstOutputURL = URL(fileURLWithPath: "/tmp/first-audio.wav")
        let secondOutputURL = URL(fileURLWithPath: "/tmp/second-audio.wav")

        try await service.startRecording(meeting: makeMeeting(), outputURL: firstOutputURL)

        let firstStopTask = Task { @MainActor in
            try await service.stopRecording()
        }

        while await pipeline.snapshot().pendingStopCount == 0 {
            await Task.yield()
        }

        let duplicateStopTask = Task { @MainActor in
            try await service.stopRecording()
        }

        #expect(await pipeline.snapshot().stopCallCount == 1)

        await pipeline.resumeStop(with: .success(()))
        try await firstStopTask.value
        try await duplicateStopTask.value

        try await service.startRecording(meeting: makeMeeting(), outputURL: secondOutputURL)

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.stopCallCount == 1)
        #expect(snapshot.startedOutputURLs == [firstOutputURL, secondOutputURL])
    }

    private func makeMeeting() -> Meeting {
        Meeting(
            title: "Test Meeting",
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            status: .recording,
            audioFilePath: "/tmp/audio.wav"
        )
    }
}

@MainActor
struct NativeAudioCapturePipelineTests {
    @Test
    func startBuildsSystemAudioOnlySessionWithCanonicalWriterSettings() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-audio.wav")
        let session = AudioCaptureStreamSessionSpy()
        let writer = AudioFileWriterSpy()
        var requestedConfiguration: NativeAudioCapturePipeline.CaptureConfiguration?

        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) {
                    configuration,
                    _
                in
                    requestedConfiguration = configuration
                    return session
                }
            },
            writerFactory: { requestedURL in
                writer.createdOutputURLs.append(requestedURL)
                return writer
            },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration()
        )

        try await pipeline.start(outputURL: outputURL)
        try await pipeline.stop()

        #expect(writer.createdOutputURLs == [outputURL])
        #expect(writer.finishCallCount == 1)
        #expect(session.startCallCount == 1)
        #expect(session.stopCallCount == 1)
        #expect(
            requestedConfiguration == NativeAudioCapturePipeline.CaptureConfiguration(
                sampleRate: 48_000,
                channelCount: 2,
                capturesSystemAudio: true,
                capturesMicrophone: false
            )
        )
    }

    @Test
    func stopKeepsCaptureStateAliveWhenNativeStopFailsAndAllowsRetry() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-retry-stop.wav")
        let session = AudioCaptureStreamSessionSpy(suspendNextStop: true)
        let writer = AudioFileWriterSpy()

        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) { _, _ in
                    session
                }
            },
            writerFactory: { _ in writer },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration()
        )

        try await pipeline.start(outputURL: outputURL)

        let firstStopTask = Task { @MainActor in
            try await pipeline.stop()
        }

        while session.pendingStopCount == 0 {
            await Task.yield()
        }

        session.resumeStop(with: .failure(AudioCapturePipelineTestError.stopFailed))

        await #expect(throws: AudioCapturePipelineTestError.stopFailed) {
            try await firstStopTask.value
        }

        #expect(session.stopCallCount == 1)
        #expect(writer.finishCallCount == 0)

        try await pipeline.stop()

        #expect(session.stopCallCount == 2)
        #expect(writer.finishCallCount == 1)
    }

    @Test
    func startFailureFinalizesWriterExactlyOnce() async throws {
        let session = AudioCaptureStreamSessionSpy(
            startResults: [.failure(AudioCapturePipelineTestError.startFailed)]
        )
        let writer = AudioFileWriterSpy()
        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) { _, _ in
                    session
                }
            },
            writerFactory: { _ in writer },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration()
        )

        await #expect(throws: AudioCapturePipelineTestError.startFailed) {
            try await pipeline.start(outputURL: URL(fileURLWithPath: "/tmp/native-pipeline-start-failure.wav"))
        }

        #expect(session.startCallCount == 1)
        #expect(writer.finishCallCount == 1)
    }
}

@MainActor
private final class RecordingServiceSpy: RecordingService {
    private var queuedStartResults: [Result<Void, Error>]
    private var queuedStopResults: [Result<Void, Error>]
    private(set) var startAttempts: [StartAttempt] = []
    private(set) var stopAttempts = 0

    init(
        queuedResults: [Result<Void, Error>] = [.success(())],
        stopResults: [Result<Void, Error>] = [.success(())]
    ) {
        queuedStartResults = queuedResults
        queuedStopResults = stopResults
    }

    func startRecording(meeting: Meeting, outputURL: URL) async throws {
        startAttempts.append(StartAttempt(meetingID: meeting.id, outputURL: outputURL))
        let nextResult = queuedStartResults.isEmpty ? .success(()) : queuedStartResults.removeFirst()
        try nextResult.get()
    }

    func stopRecording() async throws {
        stopAttempts += 1
        let nextResult = queuedStopResults.isEmpty ? .success(()) : queuedStopResults.removeFirst()
        try nextResult.get()
    }

    func snapshot() -> Snapshot {
        Snapshot(startAttempts: startAttempts, stopAttempts: stopAttempts)
    }
}

private actor AudioCapturePipelineSpy: AudioCapturePipeline {
    private var startResults: [Result<Void, Error>]
    private var stopResults: [Result<Void, Error>]
    private var suspendNextStart: Bool
    private var suspendNextStop: Bool
    private var pendingStartContinuations: [CheckedContinuation<Result<Void, Error>, Never>] = []
    private var pendingStopContinuations: [CheckedContinuation<Result<Void, Error>, Never>] = []
    private var startedOutputURLs: [URL] = []
    private var startCallCount = 0
    private var stopCallCount = 0

    init(
        startResults: [Result<Void, Error>] = [.success(())],
        stopResults: [Result<Void, Error>] = [.success(())],
        suspendNextStart: Bool = false,
        suspendNextStop: Bool = false
    ) {
        self.startResults = startResults
        self.stopResults = stopResults
        self.suspendNextStart = suspendNextStart
        self.suspendNextStop = suspendNextStop
    }

    func start(outputURL: URL) async throws {
        startCallCount += 1
        startedOutputURLs.append(outputURL)

        if suspendNextStart {
            suspendNextStart = false
            let result = await withCheckedContinuation { continuation in
                pendingStartContinuations.append(continuation)
            }
            try result.get()
            return
        }

        let result = startResults.isEmpty ? .success(()) : startResults.removeFirst()
        try result.get()
    }

    func stop() async throws {
        stopCallCount += 1

        if suspendNextStop {
            suspendNextStop = false
            let result = await withCheckedContinuation { continuation in
                pendingStopContinuations.append(continuation)
            }
            try result.get()
            return
        }

        let result = stopResults.isEmpty ? .success(()) : stopResults.removeFirst()
        try result.get()
    }

    func resumeStart(with result: Result<Void, Error>) {
        guard !pendingStartContinuations.isEmpty else {
            return
        }

        let continuation = pendingStartContinuations.removeFirst()
        continuation.resume(returning: result)
    }

    func resumeStop(with result: Result<Void, Error>) {
        guard !pendingStopContinuations.isEmpty else {
            return
        }

        let continuation = pendingStopContinuations.removeFirst()
        continuation.resume(returning: result)
    }

    func snapshot() async -> AudioCapturePipelineSnapshot {
        AudioCapturePipelineSnapshot(
            startedOutputURLs: startedOutputURLs,
            startCallCount: startCallCount,
            stopCallCount: stopCallCount,
            pendingStartCount: pendingStartContinuations.count,
            pendingStopCount: pendingStopContinuations.count
        )
    }
}

private final class AudioCaptureStreamSessionSpy: NativeAudioCapturePipeline.AudioCaptureStreamSession {
    private let startResults: [Result<Void, Error>]
    private var nextStartResultIndex = 0
    private let stopResults: [Result<Void, Error>]
    private var nextStopResultIndex = 0
    private var suspendNextStart: Bool
    private var suspendNextStop: Bool
    private var pendingStartContinuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var pendingStopContinuation: CheckedContinuation<Result<Void, Error>, Never>?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    var pendingStartCount: Int { pendingStartContinuation == nil ? 0 : 1 }
    var pendingStopCount: Int { pendingStopContinuation == nil ? 0 : 1 }

    init(
        startResults: [Result<Void, Error>] = [.success(())],
        stopResults: [Result<Void, Error>] = [.success(())],
        suspendNextStart: Bool = false,
        suspendNextStop: Bool = false
    ) {
        self.startResults = startResults
        self.stopResults = stopResults
        self.suspendNextStart = suspendNextStart
        self.suspendNextStop = suspendNextStop
    }

    func start() async throws {
        startCallCount += 1

        if suspendNextStart {
            suspendNextStart = false
            let result = await withCheckedContinuation { continuation in
                pendingStartContinuation = continuation
            }
            try result.get()
            return
        }

        let result = nextStartResult()
        try result.get()
    }

    func stop() async throws {
        stopCallCount += 1

        if suspendNextStop {
            suspendNextStop = false
            let result = await withCheckedContinuation { continuation in
                pendingStopContinuation = continuation
            }
            try result.get()
            return
        }

        let result = nextStopResult()
        try result.get()
    }

    func resumeStart(with result: Result<Void, Error>) {
        pendingStartContinuation?.resume(returning: result)
        pendingStartContinuation = nil
    }

    func resumeStop(with result: Result<Void, Error>) {
        pendingStopContinuation?.resume(returning: result)
        pendingStopContinuation = nil
    }

    private func nextStartResult() -> Result<Void, Error> {
        guard nextStartResultIndex < startResults.count else {
            return .success(())
        }

        defer { nextStartResultIndex += 1 }
        return startResults[nextStartResultIndex]
    }

    private func nextStopResult() -> Result<Void, Error> {
        guard nextStopResultIndex < stopResults.count else {
            return .success(())
        }

        defer { nextStopResultIndex += 1 }
        return stopResults[nextStopResultIndex]
    }
}

private final class AudioFileWriterSpy: NativeAudioCapturePipeline.AudioFileWriting {
    var createdOutputURLs: [URL] = []
    private(set) var appendedSampleBuffers: [CMSampleBuffer] = []
    private(set) var finishCallCount = 0

    func append(_ sampleBuffer: CMSampleBuffer) throws {
        appendedSampleBuffers.append(sampleBuffer)
    }

    func finish() throws {
        finishCallCount += 1
    }
}

@MainActor
private struct AppViewModelTestHarness {
    let fileManager: FileManager
    let context: ModelContext
    let meetingStore: MeetingStore
    let meetingFileStore: MeetingFileStore
    let recordingService: RecordingServiceSpy
    let recordingPermissions: RecordingPermissionsSpy
    let rootURL: URL

    init(
        queuedResults: [Result<Void, Error>] = [.success(())],
        stopResults: [Result<Void, Error>] = [.success(())],
        permissionResult: RecordingPermissionResult = .granted
    ) throws {
        let schema = Schema([
            Meeting.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        self.fileManager = fileManager
        self.context = context
        self.meetingStore = MeetingStore(modelContext: context)
        self.meetingFileStore = MeetingFileStore(fileManager: fileManager, rootURL: rootURL)
        self.recordingService = RecordingServiceSpy(
            queuedResults: queuedResults,
            stopResults: stopResults
        )
        self.recordingPermissions = RecordingPermissionsSpy(result: permissionResult)
        self.rootURL = rootURL
    }

    func artifactsURL(for meetingID: UUID) -> MeetingArtifacts {
        let meetingFolderURL = rootURL
            .appendingPathComponent(meetingID.uuidString, isDirectory: true)
        return MeetingArtifacts(
            meetingFolderURL: meetingFolderURL,
            audioFileURL: meetingFolderURL.appendingPathComponent("audio.wav")
        )
    }
}

private enum StartRecordingTestError: LocalizedError {
    case startFailed

    var errorDescription: String? {
        switch self {
        case .startFailed:
            "Recording startup failed"
        }
    }
}

private enum StopRecordingTestError: LocalizedError {
    case stopFailed

    var errorDescription: String? {
        switch self {
        case .stopFailed:
            "Recording shutdown failed"
        }
    }
}

private struct Snapshot {
    let startAttempts: [StartAttempt]
    let stopAttempts: Int
}

private struct StartAttempt {
    let meetingID: UUID
    let outputURL: URL
}

@MainActor
private final class RecordingPermissionsSpy: RecordingPermissions {
    private let result: RecordingPermissionResult
    private(set) var ensurePermissionsCallCount = 0

    init(result: RecordingPermissionResult = .granted) {
        self.result = result
    }

    func ensurePermissions() async -> RecordingPermissionResult {
        ensurePermissionsCallCount += 1
        return result
    }

    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(ensurePermissionsCallCount: ensurePermissionsCallCount)
    }
}

private struct PermissionSnapshot {
    let ensurePermissionsCallCount: Int
}

private struct AudioCapturePipelineSnapshot {
    let startedOutputURLs: [URL]
    let startCallCount: Int
    let stopCallCount: Int
    let pendingStartCount: Int
    let pendingStopCount: Int
}

private enum AudioCapturePipelineTestError: LocalizedError {
    case startFailed
    case stopFailed

    var errorDescription: String? {
        switch self {
        case .startFailed:
            "Audio capture start failed"
        case .stopFailed:
            "Audio capture stop failed"
        }
    }
}

@MainActor
private final class SuspendedRecordingPermissionsSpy: RecordingPermissions {
    private var continuation: CheckedContinuation<RecordingPermissionResult, Never>?
    private(set) var ensurePermissionsCallCount = 0

    func ensurePermissions() async -> RecordingPermissionResult {
        ensurePermissionsCallCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: RecordingPermissionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
