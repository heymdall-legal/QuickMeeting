import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct AppViewModelTests {
    @Test
    func generateSummaryWithoutExistingSummarySavesResult() async throws {
        let harness = try AppViewModelHarness()
        let meeting = try harness.createCompletedMeeting(summaryText: nil)
        harness.summaryService.setSummaryResult(.success("Fresh summary"))

        await harness.viewModel.generateSummary(for: meeting)

        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.summaryText == "Fresh summary")
        #expect(harness.viewModel.summaryConfirmationMeetingID == nil)
        #expect(harness.viewModel.summaryErrorMessage == nil)
    }

    @Test
    func generateSummaryWithoutConfiguredSettingsDoesNotInvokeService() async throws {
        let harness = try AppViewModelHarness(summarySettings: nil)
        let meeting = try harness.createCompletedMeeting(summaryText: nil)

        await harness.viewModel.generateSummary(for: meeting)

        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.summaryText == nil)
        #expect(harness.viewModel.summaryErrorMessage == MeetingSummaryServiceError.settingsIncomplete.localizedDescription)
        #expect(harness.summaryService.invocationCount == 0)
    }

    @Test
    func generateSummaryWithExistingSummaryRequestsConfirmation() async throws {
        let harness = try AppViewModelHarness()
        let meeting = try harness.createCompletedMeeting(summaryText: "Existing summary")

        await harness.viewModel.generateSummary(for: meeting)

        #expect(harness.viewModel.summaryConfirmationMeetingID == meeting.id)
        #expect(harness.summaryService.invocationCount == 0)
    }

    @Test
    func confirmSummaryReplacementOverwritesStoredSummary() async throws {
        let harness = try AppViewModelHarness()
        let meeting = try harness.createCompletedMeeting(summaryText: "Old summary")
        harness.summaryService.setSummaryResult(.success("New summary"))

        await harness.viewModel.generateSummary(for: meeting)
        await harness.viewModel.confirmSummaryReplacement()

        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.summaryText == "New summary")
        #expect(harness.viewModel.summaryConfirmationMeetingID == nil)
    }

    @Test
    func failedReplacementPreservesExistingSummary() async throws {
        let harness = try AppViewModelHarness()
        let meeting = try harness.createCompletedMeeting(summaryText: "Old summary")
        harness.summaryService.setSummaryResult(.failure(MeetingSummaryServiceError.responseInvalid))

        await harness.viewModel.generateSummary(for: meeting)
        await harness.viewModel.confirmSummaryReplacement()

        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.summaryText == "Old summary")
        #expect(harness.viewModel.summaryErrorMessage == MeetingSummaryServiceError.responseInvalid.localizedDescription)
    }

    @Test
    func failedSummaryErrorIsOnlyExposedForFailedMeeting() async throws {
        let harness = try AppViewModelHarness()
        let failedMeeting = try harness.createCompletedMeeting(summaryText: nil)
        let otherMeeting = try harness.createCompletedMeeting(summaryText: nil)
        harness.summaryService.setSummaryResult(.failure(MeetingSummaryServiceError.responseInvalid))

        await harness.viewModel.generateSummary(for: failedMeeting)

        #expect(harness.viewModel.summaryErrorMessage(forMeeting: failedMeeting.id) == MeetingSummaryServiceError.responseInvalid.localizedDescription)
        #expect(harness.viewModel.summaryErrorMessage(forMeeting: otherMeeting.id) == nil)
    }

    @Test
    func renameSpeakerPersistsMeetingRenameEvenWhenEnrollmentFails() async throws {
        let harness = try AppViewModelHarness(enrollmentResult: .failure(TestError.failed))
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [
                    TranscriptSpeaker(
                        id: "speaker-1",
                        displayName: "Speaker 1",
                        labelSource: .generic,
                        matchedKnownSpeakerID: nil,
                        centroid: [0.1, 0.2]
                    )
                ],
                segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
            )
        )

        try await harness.viewModel.renameSpeaker(
            meetingID: meeting.id,
            speakerID: "speaker-1",
            displayName: "Masha"
        )

        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.storedTranscript?.speakers.first?.displayName == "Masha")
        #expect(harness.viewModel.renameSpeakerErrorMessage == nil)
        #expect(harness.enrollmentService.calls.count == 1)
    }
}

@MainActor
private struct AppViewModelHarness {
    let container: ModelContainer
    let meetingStore: MeetingStore
    let meetingTranscriptStore: MeetingTranscriptStore
    let enrollmentService: StubKnownSpeakerEnrollmentService
    let summaryService: StubMeetingSummaryService
    let summarySettingsStore: StubMeetingSummarySettingsStore
    let viewModel: AppViewModel
    let meetingFileStore: MeetingFileStore

    init(
        enrollmentResult: Result<Void, Error> = .success(()),
        summarySettings: ValidatedMeetingSummarySettings? = .init(
            baseURL: "https://example.com",
            authToken: "secret-token",
            authHeaderName: "Authorization",
            modelName: "gpt-4o-mini",
            promptTemplate: "Summarize {text} on {date}"
        )
    ) throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        meetingStore = MeetingStore(modelContext: context)
        meetingTranscriptStore = MeetingTranscriptStore(meetingStore: meetingStore)
        enrollmentService = StubKnownSpeakerEnrollmentService(result: enrollmentResult)
        summaryService = StubMeetingSummaryService()
        summarySettingsStore = StubMeetingSummarySettingsStore(settingsValue: summarySettings)
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        meetingFileStore = MeetingFileStore(fileManager: .default, rootURL: rootURL)
        viewModel = AppViewModel(
            meetingStore: meetingStore,
            meetingFileStore: meetingFileStore,
            recordingService: StubRecordingService(),
            meetingSummaryService: summaryService,
            meetingSummarySettingsStore: summarySettingsStore,
            meetingTranscriptStore: meetingTranscriptStore,
            knownSpeakerEnrollmentService: enrollmentService,
            calendarIntegration: NoopCalendarIntegration()
        )
    }

    func createMeetingWithTranscript(_ transcript: StoredTranscript) throws -> Meeting {
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let artifacts = try meetingFileStore.createArtifacts(for: UUID(), startedAt: startedAt)
        FileManager.default.createFile(atPath: artifacts.audioFileURL.path, contents: Data("audio".utf8))
        let meeting = try meetingStore.createMeeting(
            id: UUID(uuidString: artifacts.meetingFolderURL.lastPathComponent) ?? UUID(),
            title: "Design Review",
            startedAt: startedAt,
            folderURL: artifacts.meetingFolderURL,
            audioFileURL: artifacts.audioFileURL
        )
        try meetingStore.finishRecording(meetingID: meeting.id, endedAt: startedAt.addingTimeInterval(60))
        try meetingStore.completeTranscription(
            meetingID: meeting.id,
            transcript: transcript,
            transcriptPreview: transcript.fullText,
            updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
        )
        return try meetingStore.fetchMeeting(id: meeting.id)
    }

    func createCompletedMeeting(summaryText: String?) throws -> Meeting {
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Alice")],
            segments: [TranscriptSegment(text: "Wrapped up launch prep.", speakerID: "speaker-1")]
        )
        let meeting = try createMeetingWithTranscript(transcript)

        if let summaryText {
            try meetingStore.saveSummary(
                meetingID: meeting.id,
                summary: summaryText,
                updatedAt: Date(timeIntervalSince1970: 1_234_568_250)
            )
        }

        return try meetingStore.fetchMeeting(id: meeting.id)
    }
}

@MainActor
private final class StubKnownSpeakerEnrollmentService: KnownSpeakerEnrolling {
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

@MainActor
private final class StubMeetingSummaryService: MeetingSummaryServicing {
    private(set) var invocationCount = 0
    private var summaryResult: Result<String, Error> = .failure(MeetingSummaryServiceError.responseInvalid)

    func setSummaryResult(_ result: Result<String, Error>) {
        summaryResult = result
    }

    func summarize(meetingID _: UUID) async throws -> String {
        invocationCount += 1
        return try summaryResult.get()
    }
}

private struct StubMeetingSummarySettingsStore: MeetingSummarySettingsStoring {
    let settingsValue: ValidatedMeetingSummarySettings?

    func settings() -> MeetingSummarySettings {
        if let settingsValue {
            return MeetingSummarySettings(
                baseURL: settingsValue.baseURL,
                authToken: settingsValue.authToken,
                authHeaderName: settingsValue.authHeaderName,
                modelName: settingsValue.modelName,
                promptTemplate: settingsValue.promptTemplate
            )
        }

        return MeetingSummarySettings(
            baseURL: nil,
            authToken: nil,
            authHeaderName: nil,
            modelName: nil,
            promptTemplate: nil
        )
    }

    func validatedSettings() -> ValidatedMeetingSummarySettings? {
        settingsValue
    }

    func saveSettings(_: MeetingSummarySettings) {}
}

@MainActor
private final class StubRecordingService: RecordingService {
    func startRecording(meeting _: Meeting, outputURL _: URL) async throws {}
    func stopRecording() async throws {}
}

private enum TestError: Error {
    case failed
}
