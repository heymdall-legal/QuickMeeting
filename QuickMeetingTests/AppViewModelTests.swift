import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct AppViewModelTests {
    @Test
    func finishingRecordingStartsTranscriptionWhenEnabled() async throws {
        let transcriptionService = StubTranscriptionService()
        let settingsStore = makeTranscriptionSettingsStore(isAutomaticEnabled: true)
        let harness = try AppViewModelHarness(
            transcriptionService: transcriptionService,
            transcriptionSettingsStore: settingsStore
        )

        await harness.viewModel.startRecording()
        let meetingID = try #require(harness.viewModel.activeOrRecoverableMeetingID)
        await harness.viewModel.stopRecording()
        await Task.yield()

        #expect(transcriptionService.meetingIDs == [meetingID])
        #expect(harness.viewModel.recordingState == .idle)
    }

    @Test
    func automaticallyFinishingRecordingStartsTranscriptionWhenEnabled() async throws {
        let transcriptionService = StubTranscriptionService()
        let settingsStore = makeTranscriptionSettingsStore(isAutomaticEnabled: true)
        let harness = try AppViewModelHarness(
            transcriptionService: transcriptionService,
            transcriptionSettingsStore: settingsStore
        )

        await harness.viewModel.requestAutoRecordingStart()
        let meetingID = try #require(harness.viewModel.activeOrRecoverableMeetingID)
        await harness.viewModel.requestAutoRecordingStop()
        await Task.yield()

        #expect(transcriptionService.meetingIDs == [meetingID])
        #expect(harness.viewModel.recordingState == .idle)
    }

    @Test
    func finishingRecordingDoesNotStartTranscriptionWhenDisabled() async throws {
        let transcriptionService = StubTranscriptionService()
        let harness = try AppViewModelHarness(
            transcriptionService: transcriptionService,
            transcriptionSettingsStore: makeTranscriptionSettingsStore(isAutomaticEnabled: false)
        )

        await harness.viewModel.startRecording()
        await harness.viewModel.stopRecording()
        await Task.yield()

        #expect(transcriptionService.meetingIDs.isEmpty)
        #expect(harness.viewModel.recordingState == .idle)
    }

    @Test
    func failedRecordingStopDoesNotStartTranscription() async throws {
        let transcriptionService = StubTranscriptionService()
        let harness = try AppViewModelHarness(
            recordingService: ThrowingStopRecordingService(),
            transcriptionService: transcriptionService,
            transcriptionSettingsStore: makeTranscriptionSettingsStore(isAutomaticEnabled: true)
        )

        await harness.viewModel.startRecording()
        await harness.viewModel.stopRecording()
        await Task.yield()

        #expect(transcriptionService.meetingIDs.isEmpty)
        guard case .failed = harness.viewModel.recordingState else {
            Issue.record("Expected a failed recording state")
            return
        }
    }

    @Test
    func startRecordingPersistsMatchedCalendarEventID() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let matchingEvent = UpcomingCalendarEvent(
            id: "event-123",
            title: "Calendar Design Review",
            startDate: startedAt,
            endDate: startedAt.addingTimeInterval(1_800),
            attendees: [
                UpcomingCalendarAttendee(displayName: "Masha", emailAddress: "masha@example.com")
            ]
        )
        let harness = try AppViewModelHarness(
            calendarIntegration: StubCalendarIntegration(matchingEvent: matchingEvent),
            dateProvider: { startedAt }
        )

        await harness.viewModel.startRecording()

        let meeting = try #require(try harness.meetingStore.fetchMeetings().first)
        #expect(meeting.title == "Calendar Design Review")
        #expect(meeting.attendeeNames == ["Masha"])
        #expect(meeting.calendarEventID == "event-123")
    }

    @Test
    func recordingStopsWhenMaximumDurationExpires() async throws {
        let clock = TestRecordingDeadlineClock()
        let recorder = StubRecordingService()
        let harness = try AppViewModelHarness(
            autoRecordingSettingsStore: StaticAutoRecordingSettingsStore(
                settings: AutoRecordingSettings(
                    isEnabled: false,
                    selectedApps: [],
                    startDelay: 10,
                    stopGracePeriod: 60,
                    maximumMeetingDurationHours: 3
                )
            ),
            deadlineClock: clock,
            recorder: recorder
        )

        await harness.viewModel.startRecording()
        await clock.advance(by: 10_799)
        #expect(recorder.stopCalls == 0)
        await clock.advance(by: 1)
        #expect(recorder.stopCalls == 1)
        #expect(harness.viewModel.recordingState == .idle)
    }

    @Test
    func stoppingBeforeMaximumDurationCancelsDeadline() async throws {
        let clock = TestRecordingDeadlineClock()
        let recorder = StubRecordingService()
        let harness = try AppViewModelHarness(deadlineClock: clock, recorder: recorder)

        await harness.viewModel.startRecording()
        await harness.viewModel.stopRecording()
        await clock.advance(by: 10_800)

        #expect(recorder.stopCalls == 1)
    }

    @Test
    func automaticRecordingStopsWhenMaximumDurationExpires() async throws {
        let clock = TestRecordingDeadlineClock()
        let recorder = StubRecordingService()
        let harness = try AppViewModelHarness(deadlineClock: clock, recorder: recorder)

        await harness.viewModel.requestAutoRecordingStart()
        await clock.advance(by: 10_800)

        #expect(recorder.stopCalls == 1)
    }

    @Test
    func selectCalendarEventPersistsTitleAttendeesAndCalendarEventID() async throws {
        let harness = try AppViewModelHarness()
        let meeting = try harness.createCompletedMeeting(summaryText: nil)
        let selectedEvent = UpcomingCalendarEvent(
            id: "event-correct",
            title: "Correct Calendar Meeting",
            startDate: meeting.startedAt,
            endDate: meeting.startedAt.addingTimeInterval(1_800),
            attendees: [
                UpcomingCalendarAttendee(displayName: "Masha", emailAddress: "masha@example.com"),
                UpcomingCalendarAttendee(displayName: "Ilya", emailAddress: "ilya@example.com")
            ]
        )

        harness.viewModel.selectCalendarEvent(selectedEvent, for: meeting)

        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.title == "Correct Calendar Meeting")
        #expect(reloaded.attendeeNames == ["Masha", "Ilya"])
        #expect(reloaded.calendarEventID == "event-correct")
        #expect(reloaded.storedTranscript?.fullText == "Wrapped up launch prep.")
        #expect(harness.viewModel.calendarEventSelectionErrorMessage == nil)
    }

    @Test
    func reloadCalendarEventsStoresCandidatesForMeeting() throws {
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let candidate = UpcomingCalendarEvent(
            id: "event-candidate",
            title: "Candidate Meeting",
            startDate: startedAt,
            endDate: startedAt.addingTimeInterval(1_800),
            attendees: []
        )
        let harness = try AppViewModelHarness(
            calendarIntegration: StubCalendarIntegration(candidates: [candidate])
        )
        let meeting = try harness.createCompletedMeeting(summaryText: nil)

        harness.viewModel.reloadCalendarEvents(for: meeting)

        #expect(harness.viewModel.calendarEvents(for: meeting).map(\.id) == ["event-candidate"])
    }

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

    @Test
    func updateTranscriptSegmentTextPersistsThroughTranscriptStore() async throws {
        let harness = try AppViewModelHarness()
        let segmentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(id: segmentID, text: "Original", speakerID: "speaker-1")]
            )
        )

        try await harness.viewModel.updateTranscriptSegmentText(
            meetingID: meeting.id,
            segmentID: segmentID,
            text: "Edited"
        )

        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.storedTranscript?.segments.map(\.text) == ["Edited"])
        #expect(harness.viewModel.renameSpeakerErrorMessage == nil)
    }

    @Test
    func splitTranscriptSegmentReturnsNewSegment() async throws {
        let harness = try AppViewModelHarness()
        let segmentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(id: segmentID, text: "Hello Masha", speakerID: "speaker-1")]
            )
        )

        let newSegment = try await harness.viewModel.splitTranscriptSegment(
            meetingID: meeting.id,
            segmentID: segmentID,
            cursorOffset: 5
        )

        #expect(newSegment.text == "Masha")
        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.storedTranscript?.segments.map(\.text) == ["Hello", "Masha"])
    }

    @Test
    func mergeTranscriptSegmentWithPreviousReturnsMergedSegment() async throws {
        let harness = try AppViewModelHarness()
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [
                    TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
                    TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2"),
                ],
                segments: [
                    TranscriptSegment(id: firstID, text: "First", speakerID: "speaker-1"),
                    TranscriptSegment(id: secondID, text: "Second", speakerID: "speaker-2"),
                ]
            )
        )

        let merged = try await harness.viewModel.mergeTranscriptSegmentWithPrevious(
            meetingID: meeting.id,
            segmentID: secondID
        )

        #expect(merged.id == firstID)
        #expect(merged.text == "First\nSecond")
        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        #expect(reloaded.storedTranscript?.segments.map(\.text) == ["First\nSecond"])
    }

    @Test
    func assignTranscriptSegmentTrimsSpeakerName() async throws {
        let harness = try AppViewModelHarness()
        let segmentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(id: segmentID, text: "Hello", speakerID: "speaker-1")]
            )
        )

        try await harness.viewModel.assignTranscriptSegment(
            meetingID: meeting.id,
            segmentID: segmentID,
            speakerName: " Masha "
        )

        let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
        let speaker = try #require(reloaded.storedTranscript?.speakers.first(where: { $0.displayName == "Masha" }))
        #expect(reloaded.storedTranscript?.segments.map(\.speakerID) == [speaker.id])
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
    let recorder: StubRecordingService
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
        ),
        calendarIntegration: any CalendarIntegration = NoopCalendarIntegration(),
        recordingPermissions: any RecordingPermissions = GrantedRecordingPermissions(),
        autoRecordingSettingsStore: any AutoRecordingSettingsStoring = StaticAutoRecordingSettingsStore(settings: .default),
        deadlineClock: (any RecordingDeadlineClock)? = nil,
        recorder: StubRecordingService? = nil,
        recordingService: (any RecordingService)? = nil,
        transcriptionService: (any TranscriptionServicing)? = nil,
        transcriptionSettingsStore: any TranscriptionLanguageStoring = TranscriptionSettingsStore(),
        dateProvider: @escaping () -> Date = Date.init
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
        let recorder = recorder ?? StubRecordingService()
        self.recorder = recorder
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        meetingFileStore = MeetingFileStore(fileManager: .default, rootURL: rootURL)
        viewModel = AppViewModel(
            meetingStore: meetingStore,
            meetingFileStore: meetingFileStore,
            recordingService: recordingService ?? recorder,
            transcriptionService: transcriptionService,
            transcriptionSettingsStore: transcriptionSettingsStore,
            meetingSummaryService: summaryService,
            meetingSummarySettingsStore: summarySettingsStore,
            recordingPermissions: recordingPermissions,
            meetingTranscriptStore: meetingTranscriptStore,
            knownSpeakerEnrollmentService: enrollmentService,
            calendarIntegration: calendarIntegration,
            autoRecordingSettingsStore: autoRecordingSettingsStore,
            recordingDeadlineClock: deadlineClock,
            dateProvider: dateProvider
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

private struct StubCalendarIntegration: CalendarIntegration {
    let matchingEvent: UpcomingCalendarEvent?
    let candidates: [UpcomingCalendarEvent]

    init(
        matchingEvent: UpcomingCalendarEvent? = nil,
        candidates: [UpcomingCalendarEvent] = []
    ) {
        self.matchingEvent = matchingEvent
        self.candidates = candidates
    }

    func authorizationState() -> CalendarAuthorizationState {
        .authorized
    }

    func requestAccess() async -> CalendarAuthorizationState {
        .authorized
    }

    func availableCalendars() -> [CalendarDescriptor] {
        []
    }

    func upcomingEventForToday() -> UpcomingCalendarEvent? {
        nil
    }

    func eventMatchingRecordingStart(at _: Date) -> UpcomingCalendarEvent? {
        matchingEvent
    }

    func calendarEventsForRecording(startedAt _: Date, endedAt _: Date?) -> [UpcomingCalendarEvent] {
        candidates
    }
}

private struct GrantedRecordingPermissions: RecordingPermissions {
    func ensurePermissions() async -> RecordingPermissionResult {
        .granted
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
                promptTemplate: settingsValue.promptTemplate,
                correctionModelName: nil,
                correctionPromptTemplate: nil
            )
        }

        return MeetingSummarySettings(
            baseURL: nil,
            authToken: nil,
            authHeaderName: nil,
            modelName: nil,
            promptTemplate: nil,
            correctionModelName: nil,
            correctionPromptTemplate: nil
        )
    }

    func validatedSettings() -> ValidatedMeetingSummarySettings? {
        settingsValue
    }

    func validatedCorrectionSettings() -> ValidatedLLMCorrectionSettings? {
        nil
    }

    func saveSettings(_: MeetingSummarySettings) {}
}

@MainActor
private final class StubRecordingService: RecordingService {
    private(set) var stopCalls = 0

    func startRecording(meeting _: Meeting, outputURL _: URL) async throws {}
    func stopRecording() async throws {
        stopCalls += 1
    }
}

@MainActor
private final class ThrowingStopRecordingService: RecordingService {
    func startRecording(meeting _: Meeting, outputURL _: URL) async throws {}

    func stopRecording() async throws {
        throw TestError.failed
    }
}

@MainActor
private final class StubTranscriptionService: TranscriptionServicing {
    private(set) var meetingIDs = [UUID]()

    func transcribe(meetingID: UUID) async throws {
        meetingIDs.append(meetingID)
    }
}

private struct StaticAutoRecordingSettingsStore: AutoRecordingSettingsStoring {
    let settings: AutoRecordingSettings

    func load() -> AutoRecordingSettings {
        settings
    }

    func save(_: AutoRecordingSettings) {}
}

@MainActor
private final class TestRecordingDeadlineClock: RecordingDeadlineClock {
    private var now: TimeInterval = 0
    private var operations: [
        (deadline: TimeInterval, task: TestDeadlineTask, operation: @MainActor @Sendable () async -> Void)
    ] = []

    func schedule(
        after seconds: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any RecordingDeadlineScheduledTask {
        let task = TestDeadlineTask()
        operations.append((now + seconds, task, operation))
        return task
    }

    func advance(by seconds: TimeInterval) async {
        now += seconds
        let ready = operations.filter { $0.deadline <= now }
        operations.removeAll { $0.deadline <= now }
        for item in ready where !item.task.isCancelled {
            await item.operation()
        }
    }
}

private final class TestDeadlineTask: RecordingDeadlineScheduledTask, @unchecked Sendable {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}

private enum TestError: Error {
    case failed
}

private func makeTranscriptionSettingsStore(isAutomaticEnabled: Bool) -> TranscriptionSettingsStore {
    let suiteName = "AppViewModelTests.TranscriptionSettings.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = TranscriptionSettingsStore(userDefaults: defaults)
    store.savePipelineOptions(.init(isAutomaticTranscriptionEnabled: isAutomaticEnabled))
    return store
}
