import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

struct MeetingStoreTests {
    @Test
    func createMeetingPersistsValidatedDefaultsAcrossFreshContext() throws {
        let schema = Schema([
            Meeting.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let creationContext = ModelContext(container)
        let store = MeetingStore(modelContext: creationContext)

        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let folderURL = URL(fileURLWithPath: "/tmp/meeting")
        let audioFileURL = folderURL.appendingPathComponent("audio.m4a")

        let meeting = try store.createMeeting(
            title: "Design Review",
            startedAt: startedAt,
            folderURL: folderURL,
            audioFileURL: audioFileURL
        )

        let meetingStatus = try meeting.status
        #expect(meeting.title == "Design Review")
        #expect(meeting.startedAt == startedAt)
        #expect(meeting.endedAt == nil)
        #expect(meetingStatus == .recording)
        #expect(meeting.audioFilePath == audioFileURL.standardizedFileURL.path())
        #expect(meeting.transcriptFilePath == nil)
        #expect(meeting.transcriptPreview == nil)
        #expect(meeting.duration == nil)
        #expect(meeting.calendarEventID == nil)
        #expect(meeting.id != UUID())
        #expect(meeting.createdAt == meeting.updatedAt)

        let verificationContext = ModelContext(container)
        let persistedMeetings = try verificationContext.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.count == 1)
        let persistedMeeting = try #require(persistedMeetings.first)
        let persistedStatus = try persistedMeeting.status
        #expect(persistedMeeting.id == meeting.id)
        #expect(persistedMeeting.title == "Design Review")
        #expect(persistedMeeting.audioFilePath == audioFileURL.standardizedFileURL.path())
        #expect(persistedStatus == .recording)
    }

    @Test
    func createMeetingRejectsAudioOutsideFolder() throws {
        let schema = Schema([
            Meeting.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let store = MeetingStore(modelContext: context)

        let folderURL = URL(fileURLWithPath: "/tmp/meeting")
        let audioFileURL = URL(fileURLWithPath: "/tmp/other/audio.m4a")

        #expect(throws: MeetingStoreError.audioFileOutsideRecordingFolder) {
            try store.createMeeting(
                title: "Design Review",
                startedAt: Date(timeIntervalSince1970: 1_234_567_890),
                folderURL: folderURL,
                audioFileURL: audioFileURL
            )
        }
    }

    @Test
    func finishRecordingPersistsEndedMeetingState() throws {
        let schema = Schema([
            Meeting.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let creationContext = ModelContext(container)
        let store = MeetingStore(modelContext: creationContext)

        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let endedAt = Date(timeIntervalSince1970: 1_234_567_950)
        let folderURL = URL(fileURLWithPath: "/tmp/meeting")
        let audioFileURL = folderURL.appendingPathComponent("audio.m4a")

        let meeting = try store.createMeeting(
            title: "Design Review",
            startedAt: startedAt,
            folderURL: folderURL,
            audioFileURL: audioFileURL
        )

        try store.finishRecording(meetingID: meeting.id, endedAt: endedAt)

        let verificationContext = ModelContext(container)
        let persistedMeetings = try verificationContext.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.count == 1)
        let persistedMeeting = try #require(persistedMeetings.first)
        let persistedStatus = try persistedMeeting.status
        let meetingStatus = try meeting.status

        #expect(persistedMeeting.id == meeting.id)
        #expect(persistedStatus == .recorded)
        #expect(persistedMeeting.startedAt == startedAt)
        #expect(persistedMeeting.endedAt == endedAt)
        #expect(persistedMeeting.duration == endedAt.timeIntervalSince(startedAt))
        #expect(persistedMeeting.createdAt == meeting.createdAt)
        #expect(persistedMeeting.updatedAt == endedAt)
        #expect(meeting.endedAt == endedAt)
        #expect(meeting.duration == endedAt.timeIntervalSince(startedAt))
        #expect(meetingStatus == .recorded)
        #expect(meeting.updatedAt == endedAt)
    }

    @Test
    func createMeetingPersistsUnescapedFilesystemAudioPath() throws {
        let schema = Schema([
            Meeting.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let store = MeetingStore(modelContext: context)

        let folderURL = URL(fileURLWithPath: "/tmp/Application Support/QuickMeeting/Meeting")
        let audioFileURL = folderURL.appendingPathComponent("audio file.wav")

        let meeting = try store.createMeeting(
            title: "Design Review",
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            folderURL: folderURL,
            audioFileURL: audioFileURL
        )

        #expect(meeting.audioFilePath == "/tmp/Application Support/QuickMeeting/Meeting/audio file.wav")
        #expect(!meeting.audioFilePath.contains("%20"))
    }

    @Test
    func startTranscriptionMarksMeetingAsTranscribing() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let updatedAt = Date(timeIntervalSince1970: 1_234_568_000)

        try harness.store.startTranscription(meetingID: meeting.id, updatedAt: updatedAt)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .transcribing)
        #expect(reloaded.updatedAt == updatedAt)
    }

    @Test
    func startTranscriptionClearsExistingTranscriptMetadata() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createCompletedMeeting(
            transcriptFileName: "transcript.txt",
            transcriptPreview: "Existing transcript"
        )
        let updatedAt = Date(timeIntervalSince1970: 1_234_568_250)

        try harness.store.startTranscription(meetingID: meeting.id, updatedAt: updatedAt)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .transcribing)
        #expect(reloaded.transcriptFilePath == nil)
        #expect(reloaded.transcriptPreview == nil)
        #expect(reloaded.updatedAt == updatedAt)
    }

    @Test
    func completeTranscriptionPersistsTranscriptPathAndPreview() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let transcriptURL = harness.folderURL(for: meeting.id).appendingPathComponent("transcript.txt")
        let updatedAt = Date(timeIntervalSince1970: 1_234_568_100)

        try harness.store.completeTranscription(
            meetingID: meeting.id,
            transcriptFileURL: transcriptURL,
            transcriptPreview: "First line of transcript",
            updatedAt: updatedAt
        )

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .completed)
        #expect(reloaded.transcriptFilePath == transcriptURL.standardizedFileURL.path())
        #expect(reloaded.transcriptPreview == "First line of transcript")
        #expect(reloaded.updatedAt == updatedAt)
    }

    @Test
    func failTranscriptionMarksMeetingAsFailedWithoutRemovingTranscriptMetadata() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let transcriptURL = harness.folderURL(for: meeting.id).appendingPathComponent("transcript.txt")

        try harness.store.completeTranscription(
            meetingID: meeting.id,
            transcriptFileURL: transcriptURL,
            transcriptPreview: "Existing transcript",
            updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
        )

        let failedAt = Date(timeIntervalSince1970: 1_234_568_200)
        try harness.store.failTranscription(meetingID: meeting.id, updatedAt: failedAt)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .failed)
        #expect(reloaded.transcriptFilePath == transcriptURL.standardizedFileURL.path())
        #expect(reloaded.transcriptPreview == "Existing transcript")
        #expect(reloaded.updatedAt == failedAt)
    }
}

private struct MeetingStoreHarness {
    let container: ModelContainer
    let store: MeetingStore

    init() throws {
        let schema = Schema([
            Meeting.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        store = MeetingStore(modelContext: ModelContext(container))
    }

    func createRecordedMeeting() throws -> Meeting {
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let endedAt = startedAt.addingTimeInterval(60)
        let folderURL = URL(fileURLWithPath: "/tmp/meeting-\(UUID().uuidString)")
        let audioFileURL = folderURL.appendingPathComponent("audio.wav")
        let meeting = try store.createMeeting(
            title: "Design Review",
            startedAt: startedAt,
            folderURL: folderURL,
            audioFileURL: audioFileURL
        )
        try store.finishRecording(meetingID: meeting.id, endedAt: endedAt)
        return try reloadMeeting(id: meeting.id)
    }

    func createCompletedMeeting(
        transcriptFileName: String,
        transcriptPreview: String
    ) throws -> Meeting {
        let meeting = try createRecordedMeeting()
        let transcriptURL = folderURL(for: meeting.id).appendingPathComponent(transcriptFileName)
        try store.completeTranscription(
            meetingID: meeting.id,
            transcriptFileURL: transcriptURL,
            transcriptPreview: transcriptPreview,
            updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
        )
        return try reloadMeeting(id: meeting.id)
    }

    func reloadMeeting(id: UUID) throws -> Meeting {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { meeting in
                meeting.id == id
            }
        )
        return try #require(context.fetch(descriptor).first)
    }

    func folderURL(for meetingID: UUID) -> URL {
        URL(fileURLWithPath: "/tmp/meeting-\(meetingID.uuidString)")
    }
}
