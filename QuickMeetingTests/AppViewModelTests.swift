import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct AppViewModelTests {
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
        #expect(await harness.enrollmentService.calls.count == 1)
    }
}

@MainActor
private struct AppViewModelHarness {
    let container: ModelContainer
    let meetingStore: MeetingStore
    let meetingTranscriptStore: MeetingTranscriptStore
    let enrollmentService: StubKnownSpeakerEnrollmentService
    let viewModel: AppViewModel
    let meetingFileStore: MeetingFileStore

    init(enrollmentResult: Result<Void, Error>) throws {
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
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        meetingFileStore = MeetingFileStore(fileManager: .default, rootURL: rootURL)
        viewModel = AppViewModel(
            meetingStore: meetingStore,
            meetingFileStore: meetingFileStore,
            recordingService: StubRecordingService(),
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

@MainActor
private final class StubRecordingService: RecordingService {
    func startRecording(meeting _: Meeting, outputURL _: URL) async throws {}
    func stopRecording() async throws {}
}

private enum TestError: Error {
    case failed
}
