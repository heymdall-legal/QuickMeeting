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
                speakers: [
                    TranscriptSpeaker(
                        id: "speaker-1",
                        displayName: "Speaker 1",
                        labelSource: .bankMatched,
                        matchedKnownSpeakerID: "known-speaker-1",
                        centroid: [0.1, 0.2, 0.3]
                    )
                ],
                segments: [TranscriptSegment(text: "Hello world", speakerID: "speaker-1")]
            )
        )

        let updated = try harness.transcriptStore.renameSpeaker(id: "speaker-1", to: "Masha", in: meeting.id)

        let speaker = try #require(updated.speakers.first)
        #expect(speaker.displayName == "Masha")
        #expect(speaker.labelSource == .userAssigned)
        #expect(speaker.matchedKnownSpeakerID == nil)
        #expect(speaker.centroid == [0.1, 0.2, 0.3])
        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        let persistedSpeaker = try #require(reloaded.storedTranscript?.speakers.first)
        #expect(persistedSpeaker.displayName == "Masha")
        #expect(persistedSpeaker.labelSource == .userAssigned)
        #expect(persistedSpeaker.matchedKnownSpeakerID == nil)
        #expect(persistedSpeaker.centroid == [0.1, 0.2, 0.3])
    }

    @Test
    func renameSpeakerFailsWhenTranscriptIsMissing() throws {
        let harness = try MeetingTranscriptStoreHarness()
        let meeting = try harness.createRecordedMeeting()

        #expect(throws: MeetingTranscriptStoreError.transcriptMissing) {
            try harness.transcriptStore.renameSpeaker(id: "speaker-1", to: "Masha", in: meeting.id)
        }
    }

    @Test
    func updateSegmentTextPersistsEditedTextAndRefreshesPreview() throws {
        let harness = try MeetingTranscriptStoreHarness()
        let segmentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(id: segmentID, text: "Original", speakerID: "speaker-1")]
            )
        )

        let updated = try harness.transcriptStore.updateSegmentText(
            segmentID: segmentID,
            text: "Edited text",
            in: meeting.id
        )

        #expect(updated.segments.map(\.text) == ["Edited text"])
        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.storedTranscript?.segments.map(\.text) == ["Edited text"])
        #expect(reloaded.transcriptPreview == "Edited text")
    }

    @Test
    func splitSegmentInsertsNewSegmentImmediatelyAfterOriginal() throws {
        let harness = try MeetingTranscriptStoreHarness()
        let segmentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let followingID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [
                    TranscriptSegment(
                        id: segmentID,
                        text: "Hello Masha",
                        startTime: 3,
                        endTime: 9,
                        speakerID: "speaker-1"
                    ),
                    TranscriptSegment(
                        id: followingID,
                        text: "Next timed segment",
                        startTime: 12,
                        endTime: 18,
                        speakerID: "speaker-1"
                    ),
                ]
            )
        )

        let newSegment = try harness.transcriptStore.splitSegment(segmentID: segmentID, at: 5, in: meeting.id)

        #expect(newSegment.text == "Masha")
        #expect(newSegment.startTime == nil)
        #expect(newSegment.endTime == 9)
        #expect(newSegment.speakerID == "speaker-1")

        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        let segments = try #require(reloaded.storedTranscript?.segments)
        #expect(segments.map(\.id) == [segmentID, newSegment.id, followingID])
        #expect(segments.map(\.text) == ["Hello", "Masha", "Next timed segment"])
        #expect(segments.map(\.startTime) == [3, nil, 12])
        #expect(segments.map(\.endTime) == [nil, 9, 18])
        #expect(reloaded.transcriptPreview == "Hello\nMasha\nNext timed segment")
    }

    @Test
    func splitSegmentRejectsEmptyLeftOrRightSide() throws {
        let harness = try MeetingTranscriptStoreHarness()
        let segmentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(id: segmentID, text: "Hello", speakerID: "speaker-1")]
            )
        )

        #expect(throws: MeetingTranscriptStoreError.invalidSplitLocation) {
            try harness.transcriptStore.splitSegment(segmentID: segmentID, at: 0, in: meeting.id)
        }
        #expect(throws: MeetingTranscriptStoreError.invalidSplitLocation) {
            try harness.transcriptStore.splitSegment(segmentID: segmentID, at: 5, in: meeting.id)
        }
    }

    @Test
    func mergeSegmentWithPreviousKeepsPreviousSpeakerAndRemovesCurrentSegment() throws {
        let harness = try MeetingTranscriptStoreHarness()
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [
                    TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
                    TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2"),
                ],
                segments: [
                    TranscriptSegment(id: firstID, text: "First", startTime: 1, endTime: nil, speakerID: "speaker-1"),
                    TranscriptSegment(id: secondID, text: "Second", startTime: nil, endTime: 7, speakerID: "speaker-2"),
                ]
            )
        )

        let merged = try harness.transcriptStore.mergeSegmentWithPrevious(segmentID: secondID, in: meeting.id)

        #expect(merged.id == firstID)
        #expect(merged.text == "First\nSecond")
        #expect(merged.startTime == 1)
        #expect(merged.endTime == 7)
        #expect(merged.speakerID == "speaker-1")

        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        let segments = try #require(reloaded.storedTranscript?.segments)
        #expect(segments.map(\.id) == [firstID])
        #expect(segments.map(\.text) == ["First\nSecond"])
        #expect(segments.map(\.speakerID) == ["speaker-1"])
    }

    @Test
    func assignSegmentReusesExistingSpeakerByName() throws {
        let harness = try MeetingTranscriptStoreHarness()
        let segmentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [
                    TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
                    TranscriptSpeaker(id: "speaker-2", displayName: "Masha"),
                ],
                segments: [TranscriptSegment(id: segmentID, text: "Hello", speakerID: "speaker-1")]
            )
        )

        let updated = try harness.transcriptStore.assignSegment(
            segmentID: segmentID,
            toSpeakerNamed: " masha ",
            in: meeting.id
        )

        #expect(Set(updated.speakers.map(\.id)) == ["speaker-1", "speaker-2"])
        #expect(updated.segments.map(\.speakerID) == ["speaker-2"])
    }

    @Test
    func assignSegmentCreatesUserAssignedSpeakerForNewName() throws {
        let harness = try MeetingTranscriptStoreHarness()
        let segmentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(id: segmentID, text: "Hello", speakerID: "speaker-1")]
            )
        )

        let updated = try harness.transcriptStore.assignSegment(
            segmentID: segmentID,
            toSpeakerNamed: "Masha",
            in: meeting.id
        )

        let newSpeaker = try #require(updated.speakers.first(where: { $0.displayName == "Masha" }))
        #expect(newSpeaker.labelSource == .userAssigned)
        #expect(updated.segments.map(\.speakerID) == [newSpeaker.id])
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
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
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
