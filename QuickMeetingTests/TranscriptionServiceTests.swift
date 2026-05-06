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
        harness.settingsStore.defaultModelID = .small
        await harness.modelStore.setInstalledModels([
            .small: InstalledTranscriptionModel(sizeInBytes: 1, installedAt: nil),
        ])
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
    func transcribeRejectsWhenNoDefaultInstalledModelExists() async throws {
        let harness = try TranscriptionServiceHarness()
        let meeting = try harness.createRecordedMeeting()

        await #expect(throws: TranscriptionServiceError.noInstalledDefaultModel) {
            try await harness.service.transcribe(meetingID: meeting.id)
        }
    }

    @Test
    func transcribeRejectsWhenAnotherJobIsActive() async throws {
        let harness = try TranscriptionServiceHarness()
        let firstMeeting = try harness.createRecordedMeeting()
        let secondMeeting = try harness.createRecordedMeeting()
        harness.settingsStore.defaultModelID = .small
        await harness.modelStore.setInstalledModels([
            .small: InstalledTranscriptionModel(sizeInBytes: 1, installedAt: nil),
        ])
        await harness.backend.suspendNextRequest()

        let firstTask = Task {
            try await harness.service.transcribe(meetingID: firstMeeting.id)
        }

        while await harness.backend.snapshot().pendingRequestCount == 0 {
            await Task.yield()
        }

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
        harness.settingsStore.defaultModelID = .small
        let modelFolderURL = harness.fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        await harness.modelStore.setInstalledModels([
            .small: InstalledTranscriptionModel(sizeInBytes: 1, installedAt: nil),
        ])
        await harness.modelStore.setResolvedModelURL(modelFolderURL, for: .small)
        await harness.backend.setResult(.success(TranscriptionResult(fullText: "Transcript body", segments: [])))

        try await harness.service.transcribe(meetingID: meeting.id)

        let request = try await #require(harness.backend.snapshot().requests.first)
        #expect(request.modelFolderURL == modelFolderURL)
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
        fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        meetingFileStore = MeetingFileStore(fileManager: fileManager, rootURL: rootURL)
        service = TranscriptionService(
            meetingStore: meetingStore,
            modelStore: modelStore,
            modelSettingsStore: settingsStore,
            backend: backend,
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
    }

    private var result: Result<TranscriptionResult, Error> = .success(
        TranscriptionResult(fullText: "", segments: [])
    )
    private var shouldSuspendNextRequest = false
    private var pendingContinuation: CheckedContinuation<TranscriptionResult, Error>?
    private var pendingRequestCount = 0
    private var requests = [TranscriptionRequest]()

    func setResult(_ result: Result<TranscriptionResult, Error>) {
        self.result = result
    }

    func suspendNextRequest() {
        shouldSuspendNextRequest = true
    }

    func snapshot() -> Snapshot {
        Snapshot(pendingRequestCount: pendingRequestCount, requests: requests)
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        requests.append(request)
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
