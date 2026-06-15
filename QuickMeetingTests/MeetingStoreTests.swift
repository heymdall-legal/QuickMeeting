import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

struct MeetingStoreTests {
    @Test
    func persistedTranscriptSpeakerDefaultsToGenericWhenStoredLabelSourceIsMissing() {
        let speaker = PersistedTranscriptSpeaker(
            id: "speaker-1",
            displayName: "Speaker 1",
            labelSourceRawValue: nil,
            matchedKnownSpeakerID: nil,
            centroid: nil
        )

        #expect(speaker.value.labelSource == .generic)
    }

    @Test
    func createMeetingPersistsValidatedDefaultsAcrossFreshContext() throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
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
        #expect(meeting.attendeeNames.isEmpty)
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
        #expect(persistedMeeting.attendeeNames.isEmpty)
        #expect(persistedStatus == .recording)
    }

    @Test
    func createMeetingRejectsAudioOutsideFolder() throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
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
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
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
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
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
    func createMeetingPersistsAttendeeNamesAcrossFreshContext() throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let store = MeetingStore(modelContext: context)

        let folderURL = URL(fileURLWithPath: "/tmp/meeting")
        let audioFileURL = folderURL.appendingPathComponent("audio.m4a")

        let meeting = try store.createMeeting(
            title: "Design Review",
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            attendeeNames: ["Masha", "Ilya"],
            folderURL: folderURL,
            audioFileURL: audioFileURL
        )

        #expect(meeting.attendeeNames == ["Masha", "Ilya"])

        let verificationContext = ModelContext(container)
        let persistedMeeting = try #require(try verificationContext.fetch(FetchDescriptor<Meeting>()).first)
        #expect(persistedMeeting.attendeeNames == ["Masha", "Ilya"])
    }

    @Test
    func startTranscriptionPreservesExistingStatus() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let updatedAt = Date(timeIntervalSince1970: 1_234_568_000)

        try harness.store.startTranscription(meetingID: meeting.id, updatedAt: updatedAt)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .recorded)
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
        #expect(try reloaded.status == .completed)
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
    func saveSummaryPersistsTextAndUpdatesMeetingTimestamp() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let previousUpdatedAt = meeting.updatedAt

        try harness.store.saveSummary(
            meetingID: meeting.id,
            summary: "Short recap",
            updatedAt: Date(timeIntervalSince1970: 1_715_325_000)
        )

        let reloaded = try harness.store.fetchMeeting(id: meeting.id)
        #expect(reloaded.summaryText == "Short recap")
        #expect(reloaded.updatedAt > previousUpdatedAt)
    }

    @Test
    func saveSummaryReplacesExistingText() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        try harness.store.saveSummary(
            meetingID: meeting.id,
            summary: "Old summary",
            updatedAt: Date(timeIntervalSince1970: 1_715_325_000)
        )

        try harness.store.saveSummary(
            meetingID: meeting.id,
            summary: "New summary",
            updatedAt: Date(timeIntervalSince1970: 1_715_325_060)
        )

        let reloaded = try harness.store.fetchMeeting(id: meeting.id)
        #expect(reloaded.summaryText == "New summary")
    }

    @Test
    func startingOrCompletingTranscriptionClearsStoredSummary() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Alice")],
            segments: [TranscriptSegment(text: "First pass", speakerID: "speaker-1")]
        )
        try harness.store.saveSummary(
            meetingID: meeting.id,
            summary: "Old summary",
            updatedAt: Date(timeIntervalSince1970: 1_715_325_000)
        )

        try harness.store.startTranscription(
            meetingID: meeting.id,
            updatedAt: Date(timeIntervalSince1970: 1_715_325_060)
        )
        #expect(try harness.store.fetchMeeting(id: meeting.id).summaryText == nil)

        try harness.store.completeTranscription(
            meetingID: meeting.id,
            transcript: transcript,
            transcriptPreview: transcript.fullText,
            updatedAt: Date(timeIntervalSince1970: 1_715_325_120)
        )
        #expect(try harness.store.fetchMeeting(id: meeting.id).summaryText == nil)
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
    func renameSpeakerMarksSpeakerAsUserAssignedAndClearsMatchedKnownSpeakerID() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createCompletedMeeting(
            transcript: StoredTranscript(
                speakers: [
                    TranscriptSpeaker(
                        id: "speaker-1",
                        displayName: "Alice",
                        labelSource: .bankMatched,
                        matchedKnownSpeakerID: "known-alice",
                        centroid: [0.1, 0.2, 0.3]
                    )
                ],
                segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
            ),
            transcriptPreview: "Hello"
        )

        try harness.store.renameSpeaker(
            meetingID: meeting.id,
            speakerID: "speaker-1",
            displayName: "Masha",
            updatedAt: Date(timeIntervalSince1970: 1_234_568_200)
        )

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        let speaker = try #require(reloaded.storedTranscript?.speakers.first)
        #expect(speaker.displayName == "Masha")
        #expect(speaker.labelSource == .userAssigned)
        #expect(speaker.matchedKnownSpeakerID == nil)
        #expect(speaker.centroid == [0.1, 0.2, 0.3])
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
    func resetStuckTranscribingMeetingsMarksMeetingsAsFailed() throws {
        let harness = try MeetingStoreHarness()
        let meeting = try harness.createRecordedMeeting()
        let stuckMeeting = try harness.store.fetchMeeting(id: meeting.id)
        stuckMeeting.setStatus(.transcribing, updatedAt: Date(timeIntervalSince1970: 1_234_568_000))
        try harness.store.modelContext.save()

        let resetAt = Date(timeIntervalSince1970: 1_234_568_999)
        try harness.store.resetStuckTranscribingMeetings(updatedAt: resetAt)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .failed)
        #expect(reloaded.updatedAt == resetAt)
    }

    @Test
    func resetStuckTranscribingMeetingsDoesNotAffectOtherStatuses() throws {
        let harness = try MeetingStoreHarness()
        let recorded = try harness.createRecordedMeeting()
        let originalUpdatedAt = recorded.updatedAt

        try harness.store.resetStuckTranscribingMeetings(updatedAt: Date())

        let reloaded = try harness.reloadMeeting(id: recorded.id)
        #expect(try reloaded.status == .recorded)
        #expect(reloaded.updatedAt == originalUpdatedAt)
    }

    @Test
    func resetStuckRecordingMeetingsMarksMeetingsAsRecorded() throws {
        let harness = try MeetingStoreHarness()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let updatedAt = Date(timeIntervalSince1970: 1_234_568_000)
        let resetAt = Date(timeIntervalSince1970: 1_234_568_999)
        let folderURL = URL(fileURLWithPath: "/tmp/meeting-\(UUID().uuidString)")
        let audioFileURL = folderURL.appendingPathComponent("audio.wav")

        let meeting = try harness.store.createMeeting(
            title: "Interrupted Recording",
            startedAt: startedAt,
            folderURL: folderURL,
            audioFileURL: audioFileURL
        )
        meeting.setStatus(.recording, updatedAt: updatedAt)
        try harness.store.modelContext.save()

        try harness.store.resetStuckRecordingMeetings(updatedAt: resetAt)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .recorded)
        #expect(reloaded.endedAt == resetAt)
        #expect(reloaded.duration == resetAt.timeIntervalSince(startedAt))
        #expect(reloaded.updatedAt == resetAt)
    }

    @Test
    func resetStuckRecordingMeetingsDoesNotAffectFinishedMeetings() throws {
        let harness = try MeetingStoreHarness()
        let recorded = try harness.createRecordedMeeting()
        let originalEndedAt = recorded.endedAt
        let originalDuration = recorded.duration
        let originalUpdatedAt = recorded.updatedAt

        try harness.store.resetStuckRecordingMeetings(
            updatedAt: Date(timeIntervalSince1970: 1_234_568_999)
        )

        let reloaded = try harness.reloadMeeting(id: recorded.id)
        #expect(try reloaded.status == .recorded)
        #expect(reloaded.endedAt == originalEndedAt)
        #expect(reloaded.duration == originalDuration)
        #expect(reloaded.updatedAt == originalUpdatedAt)
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

    @Test
    func newMeetingHasNilWaveformSamples() throws {
        let harness = try MeetingStoreHarness()
        let folderURL = URL(fileURLWithPath: "/tmp/meeting-wf-\(UUID().uuidString)")
        let audioURL = folderURL.appendingPathComponent("audio.m4a")
        let meeting = try harness.store.createMeeting(
            title: "Waveform Test",
            startedAt: Date(),
            folderURL: folderURL,
            audioFileURL: audioURL
        )
        #expect(meeting.waveformSamples == nil)
    }

    @Test
    func storeWaveformPersistsSamplesAcrossContexts() throws {
        let harness = try MeetingStoreHarness()
        let folderURL = URL(fileURLWithPath: "/tmp/meeting-wf2-\(UUID().uuidString)")
        let audioURL = folderURL.appendingPathComponent("audio.m4a")
        let meeting = try harness.store.createMeeting(
            title: "Waveform Persist",
            startedAt: Date(),
            folderURL: folderURL,
            audioFileURL: audioURL
        )
        let samples = (0..<300).map { Double($0) / 299.0 }
        try harness.store.storeWaveform(meetingID: meeting.id, samples: samples)
        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(reloaded.waveformSamples?.count == 300)
        #expect(abs((reloaded.waveformSamples?.last ?? -1) - 1.0) < 0.001)
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
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
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
