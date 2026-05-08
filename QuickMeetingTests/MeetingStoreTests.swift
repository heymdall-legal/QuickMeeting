import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

struct MeetingStoreTests {
    @Test
    func createMeetingPersistsValidatedDefaultsAcrossFreshContext() throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
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
        #expect(meeting.transcriptPreview == nil)
        #expect(meeting.transcriptSpeakers.isEmpty)
        #expect(meeting.transcriptSegments.isEmpty)
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
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
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
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
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
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
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
            transcript: StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(text: "Existing transcript", speakerID: "speaker-1")]
            ),
            transcriptPreview: "Existing transcript"
        )
        let updatedAt = Date(timeIntervalSince1970: 1_234_568_250)

        try harness.store.startTranscription(meetingID: meeting.id, updatedAt: updatedAt)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .transcribing)
        #expect(reloaded.transcriptPreview == nil)
        #expect(reloaded.transcriptSpeakers.isEmpty)
        #expect(reloaded.transcriptSegments.isEmpty)
        #expect(reloaded.updatedAt == updatedAt)
    }

    @Test
    func completeTranscriptionPersistsStructuredTranscriptDataAndPreview() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let updatedAt = Date(timeIntervalSince1970: 1_234_568_100)
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "First line of transcript", startTime: 0, endTime: 1, speakerID: "speaker-1")]
        )

        try harness.store.completeTranscription(
            meetingID: meeting.id,
            transcript: transcript,
            transcriptPreview: "First line of transcript",
            updatedAt: updatedAt
        )

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .completed)
        #expect(reloaded.transcriptPreview == "First line of transcript")
        #expect(reloaded.transcriptSpeakers.map(\.displayName) == ["Speaker 1"])
        #expect(reloaded.transcriptSegments.map(\.text) == ["First line of transcript"])
        #expect(reloaded.updatedAt == updatedAt)
    }

    @Test
    func failTranscriptionMarksMeetingAsFailedWithoutRemovingTranscriptMetadata() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Existing transcript", speakerID: "speaker-1")]
        )

        try harness.store.completeTranscription(
            meetingID: meeting.id,
            transcript: transcript,
            transcriptPreview: "Existing transcript",
            updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
        )

        let failedAt = Date(timeIntervalSince1970: 1_234_568_200)
        try harness.store.failTranscription(meetingID: meeting.id, updatedAt: failedAt)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .failed)
        #expect(reloaded.transcriptPreview == "Existing transcript")
        #expect(reloaded.transcriptSpeakers.map(\.displayName) == ["Speaker 1"])
        #expect(reloaded.transcriptSegments.map(\.text) == ["Existing transcript"])
        #expect(reloaded.updatedAt == failedAt)
    }

    @Test
    func renameSpeakerUpdatesPersistedMeetingTranscript() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()

        try harness.store.completeTranscription(
            meetingID: meeting.id,
            transcript: StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
            ),
            transcriptPreview: "Hello",
            updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
        )

        let renamedAt = Date(timeIntervalSince1970: 1_234_568_200)
        try harness.store.renameSpeaker(
            meetingID: meeting.id,
            speakerID: "speaker-1",
            displayName: "Masha",
            updatedAt: renamedAt
        )

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(reloaded.transcriptSpeakers.map(\.displayName) == ["Masha"])
        #expect(reloaded.transcriptSegments.map(\.speakerID) == ["speaker-1"])
        #expect(reloaded.updatedAt == renamedAt)
    }

    @Test
    func renameMeetingUpdatesPersistedTitleAndUpdatedAt() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let renamedAt = Date(timeIntervalSince1970: 1_234_568_300)

        try harness.store.renameMeeting(
            meetingID: meeting.id,
            title: "Renamed Review",
            updatedAt: renamedAt
        )

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(reloaded.title == "Renamed Review")
        #expect(reloaded.updatedAt == renamedAt)
    }

    @Test
    func renameMeetingRejectsEmptyTrimmedTitle() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let originalUpdatedAt = meeting.updatedAt

        #expect(throws: MeetingStoreError.invalidMeetingTitle) {
            try harness.store.renameMeeting(
                meetingID: meeting.id,
                title: "   ",
                updatedAt: Date(timeIntervalSince1970: 1_234_568_300)
            )
        }

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(reloaded.title == "Design Review")
        #expect(reloaded.updatedAt == originalUpdatedAt)
    }
}

private struct MeetingStoreHarness {
    let container: ModelContainer
    let store: MeetingStore

    init() throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
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
        transcript: StoredTranscript,
        transcriptPreview: String
    ) throws -> Meeting {
        let meeting = try createRecordedMeeting()
        try store.completeTranscription(
            meetingID: meeting.id,
            transcript: transcript,
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
}
