import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct TranscriptionServiceTests {
    @Test
    func transcribeRecordedMeetingWritesTranscriptAndCompletesMeeting() async throws {
        let harness = try TranscriptionServiceHarness()
        let meeting = try harness.createRecordedMeeting()
        await harness.installDefaultModel(.small)
        await harness.backend.setResult(.success(
            TranscriptionResult(
                fullText: "Transcript body",
                segments: [TranscriptSegment(text: "Transcript body", startTime: 0, endTime: 1)]
            )
        ))

        try await harness.service.transcribe(meetingID: meeting.id)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .completed)
        #expect(reloaded.transcriptPreview == "Transcript body")
        #expect(reloaded.transcriptFilePath?.hasSuffix("/transcript.txt") == true)
        let transcriptPath = try #require(reloaded.transcriptFilePath)
        #expect(try String(contentsOfFile: transcriptPath) == "Transcript body")
    }

    @Test
    func transcribeCompletedMeetingClearsAndReplacesTranscript() async throws {
        let harness = try TranscriptionServiceHarness()
        let meeting = try harness.createCompletedMeeting(
            transcriptText: "Old transcript",
            preview: "Old transcript"
        )
        await harness.installDefaultModel(.small)
        await harness.backend.setResult(.success(
            TranscriptionResult(
                fullText: "New transcript",
                segments: [TranscriptSegment(text: "New transcript", startTime: 0, endTime: 1)]
            )
        ))

        try await harness.service.transcribe(meetingID: meeting.id)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .completed)
        #expect(reloaded.transcriptPreview == "New transcript")
        let transcriptPath = try #require(reloaded.transcriptFilePath)
        #expect(try String(contentsOfFile: transcriptPath) == "New transcript")
    }

    @Test
    func transcribeRejectsWhenNoDefaultInstalledModelExists() async throws {
        let harness = try TranscriptionServiceHarness()
        let meeting = try harness.createRecordedMeeting()

        await #expect(throws: TranscriptionServiceError.noInstalledDefaultModel) {
            try await harness.service.transcribe(meetingID: meeting.id)
        }
    }

    @Test
    func transcribeCompletedMeetingWithMissingModelDoesNotClearExistingTranscript() async throws {
        let harness = try TranscriptionServiceHarness()
        let meeting = try harness.createCompletedMeeting(
            transcriptText: "Existing transcript",
            preview: "Existing transcript"
        )

        await #expect(throws: TranscriptionServiceError.noInstalledDefaultModel) {
            try await harness.service.transcribe(meetingID: meeting.id)
        }

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .completed)
        #expect(reloaded.transcriptPreview == "Existing transcript")
        #expect(reloaded.transcriptFilePath != nil)
    }

    @Test
    func transcribeRejectsWhenAnotherJobIsActive() async throws {
        let harness = try TranscriptionServiceHarness()
        let firstMeeting = try harness.createRecordedMeeting()
        let secondMeeting = try harness.createRecordedMeeting()
        await harness.installDefaultModel(.small)
        await harness.backend.suspendNextRequest()

        let firstTask = Task {
            try await harness.service.transcribe(meetingID: firstMeeting.id)
        }

        await harness.backend.waitForSuspendedRequest()

        await #expect(throws: TranscriptionServiceError.transcriptionAlreadyActive) {
            try await harness.service.transcribe(meetingID: secondMeeting.id)
        }

        await harness.backend.resume(with: .success(TranscriptionResult(fullText: "Done", segments: [])))
        try await firstTask.value
    }

    @Test
    func transcribePassesResolvedInstalledModelFolderToBackend() async throws {
        let harness = try TranscriptionServiceHarness()
        let meeting = try harness.createRecordedMeeting()
        let modelFolderURL = harness.fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        await harness.installDefaultModel(.small, modelFolderURL: modelFolderURL)
        await harness.backend.setResult(.success(TranscriptionResult(fullText: "Transcript body", segments: [])))

        try await harness.service.transcribe(meetingID: meeting.id)

        let request = try await #require(harness.backend.snapshot().requests.first)
        #expect(request.modelFolderURL == modelFolderURL)
    }

    @Test
    func transcribePassesProgressCallbackToBackend() async throws {
        let harness = try TranscriptionServiceHarness()
        let meeting = try harness.createRecordedMeeting()
        await harness.installDefaultModel(.small)
        await harness.backend.setResult(.success(TranscriptionResult(fullText: "Transcript body", segments: [])))

        try await harness.service.transcribe(meetingID: meeting.id)

        let snapshot = await harness.backend.snapshot()
        #expect(snapshot.requestHasProgressCallback == [true])
    }

    @Test
    func transcribeTracksProgressAndClearsItAfterSuccess() async throws {
        let harness = try TranscriptionServiceHarness()
        let meeting = try harness.createRecordedMeeting()
        await harness.installDefaultModel(.small)
        await harness.backend.setProgressUpdates([0.2, 0.6, 1.0])
        await harness.backend.setResult(.success(TranscriptionResult(fullText: "Done", segments: [])))

        try await harness.service.transcribe(meetingID: meeting.id)

        let snapshot = await harness.backend.snapshot()
        #expect(snapshot.reportedProgress == [0.2, 0.6, 1.0])
        #expect(harness.progressCenter.progress(for: meeting.id) == nil)
    }

    @Test
    func transcribeClearsProgressAfterFailure() async throws {
        let harness = try TranscriptionServiceHarness()
        let meeting = try harness.createRecordedMeeting()
        await harness.installDefaultModel(.small)
        await harness.backend.setProgressUpdates([0.35])
        await harness.backend.setResult(.failure(TestTranscriptionError.failed))

        await #expect(throws: TestTranscriptionError.failed) {
            try await harness.service.transcribe(meetingID: meeting.id)
        }

        let snapshot = await harness.backend.snapshot()
        #expect(snapshot.reportedProgress == [0.35])
        #expect(harness.progressCenter.progress(for: meeting.id) == nil)
    }
}

@MainActor
private struct TranscriptionServiceHarness {
    let container: ModelContainer
    let context: ModelContext
    let meetingStore: MeetingStore
    let settingsStore: ModelSettingsStore
    let modelStore: FakeWhisperModelStore
    let backend: SuspendedWhisperTranscriptionBackend
    let progressCenter: TranscriptionProgressCenter
    let fileManager: FileManager
    let meetingFileStore: MeetingFileStore
    let service: TranscriptionService

    init() throws {
        let schema = Schema([
            Meeting.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        meetingStore = MeetingStore(modelContext: context)
        settingsStore = ModelSettingsStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        modelStore = FakeWhisperModelStore()
        backend = SuspendedWhisperTranscriptionBackend()
        progressCenter = TranscriptionProgressCenter()
        fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        meetingFileStore = MeetingFileStore(fileManager: fileManager, rootURL: rootURL)
        service = TranscriptionService(
            meetingStore: meetingStore,
            modelStore: modelStore,
            modelSettingsStore: settingsStore,
            backend: backend,
            progressCenter: progressCenter,
            artifactWriter: TranscriptionArtifactWriter(fileManager: fileManager),
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

    func createCompletedMeeting(
        transcriptText: String,
        preview: String
    ) throws -> Meeting {
        let meeting = try createRecordedMeeting()
        let transcriptURL = meetingFileStore.rootURL
            .appendingPathComponent(meeting.id.uuidString, isDirectory: true)
            .appendingPathComponent("transcript.txt")
        fileManager.createFile(atPath: transcriptURL.path, contents: Data(transcriptText.utf8))
        try meetingStore.completeTranscription(
            meetingID: meeting.id,
            transcriptFileURL: transcriptURL,
            transcriptPreview: preview,
            updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
        )
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

    func installDefaultModel(
        _ modelID: TranscriptionModelID,
        modelFolderURL: URL? = nil
    ) async {
        settingsStore.defaultModelID = modelID
        await modelStore.setInstalledModels([
            modelID: InstalledTranscriptionModel(sizeInBytes: 1, installedAt: nil),
        ])

        let resolvedModelFolderURL = modelFolderURL ?? fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        await modelStore.setResolvedModelURL(resolvedModelFolderURL, for: modelID)
    }
}

private actor FakeWhisperModelStore: WhisperModelStore {
    private var installedModelsByID: [TranscriptionModelID: InstalledTranscriptionModel] = [:]
    private var modelURLsByID = [TranscriptionModelID: URL]()

    func setInstalledModels(_ models: [TranscriptionModelID: InstalledTranscriptionModel]) {
        installedModelsByID = models
    }

    func setResolvedModelURL(_ url: URL, for modelID: TranscriptionModelID) {
        modelURLsByID[modelID] = url
    }

    func installedModels() async throws -> [TranscriptionModelID: InstalledTranscriptionModel] {
        installedModelsByID
    }

    func installedModelURL(for model: TranscriptionModel) async throws -> URL? {
        let modelID = await model.id
        return modelURLsByID[modelID]
    }

    func downloadModel(
        _ model: TranscriptionModel,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws {}

    func deleteModel(_ model: TranscriptionModel) async throws {}
}

private actor SuspendedWhisperTranscriptionBackend: WhisperTranscriptionBackend {
    struct Snapshot {
        let pendingRequestCount: Int
        let requests: [TranscriptionRequest]
        let requestHasProgressCallback: [Bool]
        let reportedProgress: [Double]
    }

    private var result: Result<TranscriptionResult, Error> = .success(
        TranscriptionResult(fullText: "", segments: [])
    )
    private var shouldSuspendNextRequest = false
    private var pendingContinuation: CheckedContinuation<TranscriptionResult, Error>?
    private var pendingRequestCount = 0
    private var requests = [TranscriptionRequest]()
    private var requestHasProgressCallback = [Bool]()
    private var progressUpdates = [Double]()
    private var reportedProgress = [Double]()

    func setResult(_ result: Result<TranscriptionResult, Error>) {
        self.result = result
    }

    func setProgressUpdates(_ progressUpdates: [Double]) {
        self.progressUpdates = progressUpdates
    }

    func suspendNextRequest() {
        shouldSuspendNextRequest = true
    }

    func snapshot() -> Snapshot {
        Snapshot(
            pendingRequestCount: pendingRequestCount,
            requests: requests,
            requestHasProgressCallback: requestHasProgressCallback,
            reportedProgress: reportedProgress
        )
    }

    func waitForSuspendedRequest() async {
        while pendingRequestCount == 0 {
            await Task.yield()
        }
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        requests.append(request)
        requestHasProgressCallback.append(request.onProgress != nil)
        for progress in progressUpdates {
            request.onProgress?(progress)
            reportedProgress.append(progress)
        }
        if shouldSuspendNextRequest {
            shouldSuspendNextRequest = false
            pendingRequestCount += 1
            return try await withCheckedThrowingContinuation { continuation in
                pendingContinuation = continuation
            }
        }

        return try result.get()
    }

    func resume(with result: Result<TranscriptionResult, Error>) {
        pendingRequestCount = max(0, pendingRequestCount - 1)
        pendingContinuation?.resume(with: result)
        pendingContinuation = nil
    }
}

private enum TestTranscriptionError: LocalizedError {
    case failed

    var errorDescription: String? {
        switch self {
        case .failed:
            return "Transcription failed"
        }
    }
}
