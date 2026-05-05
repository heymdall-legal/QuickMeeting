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
}
