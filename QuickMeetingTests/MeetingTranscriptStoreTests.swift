import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

struct MeetingTranscriptStoreTests {
    @Test
    func renameSpeakerUpdatesStoredTranscriptForMeeting() throws {
        let harness = try MeetingTranscriptStoreHarness()
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(text: "Hello world", speakerID: "speaker-1")]
            )
        )

        let updated = try harness.transcriptStore.renameSpeaker(id: "speaker-1", to: "Masha", in: meeting.id)

        #expect(updated.speakers.first?.displayName == "Masha")
        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.transcriptSpeakers.map(\.displayName) == ["Masha"])
    }

    @Test
    func renameSpeakerFailsWhenTranscriptIsMissing() throws {
        let harness = try MeetingTranscriptStoreHarness()
        let meeting = try harness.createRecordedMeeting()

        #expect(throws: MeetingTranscriptStoreError.sidecarMissing) {
            try harness.transcriptStore.renameSpeaker(id: "speaker-1", to: "Masha", in: meeting.id)
        }
    }
}

private struct MeetingTranscriptStoreHarness {
    let container: ModelContainer
    let meetingStore: MeetingStore
    let transcriptStore: MeetingTranscriptStore

    init() throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        meetingStore = MeetingStore(modelContext: ModelContext(container))
        transcriptStore = MeetingTranscriptStore(meetingStore: meetingStore)
    }

    func createRecordedMeeting() throws -> Meeting {
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let endedAt = startedAt.addingTimeInterval(60)
        let folderURL = URL(fileURLWithPath: "/tmp/meeting-\(UUID().uuidString)")
        let audioFileURL = folderURL.appendingPathComponent("audio.wav")
        let meeting = try meetingStore.createMeeting(
            title: "Design Review",
            startedAt: startedAt,
            folderURL: folderURL,
            audioFileURL: audioFileURL
        )
        try meetingStore.finishRecording(meetingID: meeting.id, endedAt: endedAt)
        return try meetingStore.fetchMeeting(id: meeting.id)
    }

    func createMeetingWithTranscript(_ transcript: StoredTranscript) throws -> Meeting {
        let meeting = try createRecordedMeeting()
        try meetingStore.completeTranscription(
            meetingID: meeting.id,
            transcript: transcript,
            transcriptPreview: transcript.fullText,
            updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
        )
        return try meetingStore.fetchMeeting(id: meeting.id)
    }
}
