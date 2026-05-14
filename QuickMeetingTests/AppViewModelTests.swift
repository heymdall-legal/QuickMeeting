import AVFAudio
import CoreMedia
import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct AppViewModelTests {
    @Test
    func startRecordingTransitionsFromIdleToRecording() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            dateProvider: { startedAt },
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        #expect(viewModel.recordingState == .idle)

        await viewModel.startRecording()

        #expect(viewModel.recordingState == .recording(meetingID: meetingID))

        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.count == 1)

        let persistedMeeting = try #require(persistedMeetings.first)
        #expect(persistedMeeting.id == meetingID)
        #expect(persistedMeeting.startedAt == startedAt)
        #expect(
            persistedMeeting.audioFilePath
                == harness.artifactsURL(for: meetingID).audioFileURL
                .standardizedFileURL
                .path()
        )

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 1)
        #expect(snapshot.startAttempts.first?.meetingID == meetingID)
        #expect(snapshot.startAttempts.first?.outputURL == harness.artifactsURL(for: meetingID).audioFileURL)
    }

    @Test
    func startRecordingFailureRollsBackPersistedMeetingAndArtifacts() async throws {
        let harness = try AppViewModelTestHarness(
            queuedResults: [.failure(StartRecordingTestError.startFailed)]
        )
        let meetingID = UUID()
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        await viewModel.startRecording()

        #expect(viewModel.recordingState == .failed(message: "Recording startup failed"))
        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.isEmpty)
        #expect(!harness.fileManager.fileExists(atPath: harness.artifactsURL(for: meetingID).meetingFolderURL.path))

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 1)
        #expect(snapshot.stopAttempts == 1)
        #expect(snapshot.startAttempts.first?.meetingID == meetingID)
    }

    @Test
    func startRecordingAllowsRetryFromFailedState() async throws {
        let harness = try AppViewModelTestHarness(
            queuedResults: [
                .failure(StartRecordingTestError.startFailed),
                .success(())
            ]
        )
        let firstMeetingID = UUID()
        let secondMeetingID = UUID()
        var meetingIDs = [firstMeetingID, secondMeetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        await viewModel.startRecording()
        #expect(viewModel.recordingState == .failed(message: "Recording startup failed"))

        await viewModel.startRecording()

        #expect(viewModel.recordingState == .recording(meetingID: secondMeetingID))
        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.count == 1)
        #expect(persistedMeetings.first?.id == secondMeetingID)
        #expect(!harness.fileManager.fileExists(atPath: harness.artifactsURL(for: firstMeetingID).meetingFolderURL.path))
        #expect(harness.fileManager.fileExists(atPath: harness.artifactsURL(for: secondMeetingID).meetingFolderURL.path))

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 2)
        #expect(snapshot.startAttempts.map(\.meetingID) == [firstMeetingID, secondMeetingID])
    }

    @Test
    func startRecordingFailsEarlyWhenPermissionsAreDenied() async throws {
        let harness = try AppViewModelTestHarness(
            permissionResult: .denied(message: "Screen recording permission is required.")
        )
        let meetingID = UUID()
        var meetingIDWasRequested = false
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            meetingIDProvider: {
                meetingIDWasRequested = true
                return meetingIDs.removeFirst()
            }
        )

        await viewModel.startRecording()

        #expect(viewModel.recordingState == .failed(message: "Screen recording permission is required."))
        #expect(harness.recordingPermissions.snapshot().ensurePermissionsCallCount == 1)
        #expect(harness.recordingService.snapshot().startAttempts.isEmpty)
        #expect(!meetingIDWasRequested)

        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.isEmpty)
        #expect(!harness.fileManager.fileExists(atPath: harness.artifactsURL(for: meetingID).meetingFolderURL.path))
    }

    @Test
    func startRecordingSerializesWhileWaitingForPermissions() async throws {
        let harness = try AppViewModelTestHarness()
        let permissionSpy = SuspendedRecordingPermissionsSpy()
        let meetingID = UUID()
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: permissionSpy,
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        let firstStart = Task { @MainActor in
            await viewModel.startRecording()
        }

        while permissionSpy.ensurePermissionsCallCount == 0 {
            await Task.yield()
        }

        await viewModel.startRecording()

        #expect(viewModel.recordingState == .starting)
        #expect(harness.recordingService.snapshot().startAttempts.isEmpty)

        permissionSpy.resume(with: .granted)
        await firstStart.value

        #expect(viewModel.recordingState == .recording(meetingID: meetingID))
        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.count == 1)

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 1)
        #expect(snapshot.startAttempts.first?.meetingID == meetingID)
    }

    @Test
    func stopRecordingTransitionsToIdleAndFinishesMeeting() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let endedAt = startedAt.addingTimeInterval(95)
        var capturedDates = [startedAt, endedAt]
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            dateProvider: { capturedDates.removeFirst() },
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        #expect(viewModel.canStartRecording)
        #expect(!viewModel.canStopRecording)

        await viewModel.startRecording()

        #expect(!viewModel.canStartRecording)
        #expect(viewModel.canStopRecording)

        await viewModel.stopRecording()

        #expect(viewModel.recordingState == .idle)
        #expect(viewModel.canStartRecording)
        #expect(!viewModel.canStopRecording)

        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.count == 1)

        let persistedMeeting = try #require(persistedMeetings.first)
        #expect(persistedMeeting.id == meetingID)
        #expect(persistedMeeting.endedAt == endedAt)
        #expect(persistedMeeting.duration == 95)
        #expect(try persistedMeeting.status == .recorded)

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 1)
        #expect(snapshot.stopAttempts == 1)
    }

    @Test
    func stopRecordingFailureKeepsRecoverableMeetingAvailableToTheUI() async throws {
        let harness = try AppViewModelTestHarness(
            stopResults: [.failure(StopRecordingTestError.stopFailed)]
        )
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            dateProvider: { startedAt },
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        await viewModel.startRecording()
        await viewModel.stopRecording()

        #expect(viewModel.recordingState == .failed(message: "Recording shutdown failed"))
        #expect(viewModel.activeOrRecoverableMeetingID == meetingID)
        #expect(!viewModel.canStartRecording)
        #expect(viewModel.canStopRecording)

        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        let persistedMeeting = try #require(persistedMeetings.first)
        #expect(try persistedMeeting.status == .recording)
        #expect(persistedMeeting.endedAt == nil)

        let snapshot = harness.recordingService.snapshot()
        #expect(snapshot.startAttempts.count == 1)
        #expect(snapshot.stopAttempts == 1)
    }

    @Test
    func deleteMeetingRemovesPersistedMeetingAndArtifacts() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let artifacts = try harness.meetingFileStore.createArtifacts(for: meetingID, startedAt: startedAt)
        harness.fileManager.createFile(atPath: artifacts.audioFileURL.path, contents: Data("stub".utf8))
        let meeting = try harness.meetingStore.createMeeting(
            id: meetingID,
            title: "Delete Me",
            startedAt: startedAt,
            folderURL: artifacts.meetingFolderURL,
            audioFileURL: artifacts.audioFileURL
        )
        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions
        )

        viewModel.deleteMeeting(meeting)

        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(persistedMeetings.isEmpty)
        #expect(!harness.fileManager.fileExists(atPath: artifacts.audioFileURL.path))
        #expect(!harness.fileManager.fileExists(atPath: artifacts.meetingFolderURL.path))
        #expect(viewModel.deletionErrorMessage == nil)
    }

    @Test
    func deleteMeetingIgnoresTheActiveOrRecoverableMeeting() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        var dates = [startedAt]
        var meetingIDs = [meetingID]
        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            dateProvider: { dates.removeFirst() },
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        await viewModel.startRecording()

        let persistedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        let meeting = try #require(persistedMeetings.first)
        #expect(!viewModel.canDeleteMeeting(meeting))

        viewModel.deleteMeeting(meeting)

        let reloadedMeetings = try harness.context.fetch(FetchDescriptor<Meeting>())
        #expect(reloadedMeetings.count == 1)
        #expect(reloadedMeetings.first?.id == meetingID)
        #expect(viewModel.deletionErrorMessage == nil)
    }

    @Test
    func transcribeMeetingDelegatesToServiceAndClearsPreviousError() async throws {
        let harness = try AppViewModelTestHarness()
        let meeting = try harness.createRecordedMeeting()
        let viewModel = harness.makeViewModel()

        await viewModel.transcribeMeeting(meeting)

        #expect(harness.transcriptionService.snapshot().transcribedMeetingIDs == [meeting.id])
        #expect(viewModel.transcriptionErrorMessage == nil)
    }

    @Test
    func transcribeMeetingStoresTheFailureMessageForUI() async throws {
        let harness = try AppViewModelTestHarness(
            transcriptionResults: [.failure(TranscriptionActionTestError.failed)]
        )
        let meeting = try harness.createRecordedMeeting()
        let viewModel = harness.makeViewModel()

        await viewModel.transcribeMeeting(meeting)

        #expect(viewModel.transcriptionErrorMessage == "Transcription failed")
    }

    @Test
    func loadUpcomingCalendarEventPublishesNextEventForHome() async throws {
        let harness = try AppViewModelTestHarness()
        let expectedEvent = UpcomingCalendarEvent(
            title: "Design Review",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600),
            attendees: []
        )
        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            calendarIntegration: StubCalendarIntegration(upcomingEvent: expectedEvent)
        )

        await viewModel.loadUpcomingCalendarEvent()

        #expect(viewModel.upcomingCalendarEvent?.title == "Design Review")
    }

    @Test
    func startRecordingUsesMatchingCalendarEventTitleWhenAvailable() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_746_692_100)
        var meetingIDs = [meetingID]
        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            calendarIntegration: StubCalendarIntegration(
                matchingEvent: UpcomingCalendarEvent(
                    title: "Design Review",
                    startDate: startedAt.addingTimeInterval(300),
                    endDate: startedAt.addingTimeInterval(2_100),
                    attendees: []
                )
            ),
            dateProvider: { startedAt },
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        await viewModel.startRecording()

        let persistedMeeting = try #require(try harness.context.fetch(FetchDescriptor<Meeting>()).first)
        #expect(persistedMeeting.title == "Design Review")
    }

    @Test
    func startRecordingPersistsAttendeeNamesFromMatchingCalendarEvent() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_746_692_100)
        var meetingIDs = [meetingID]
        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            calendarIntegration: StubCalendarIntegration(
                matchingEvent: UpcomingCalendarEvent(
                    title: "Design Review",
                    startDate: startedAt.addingTimeInterval(300),
                    endDate: startedAt.addingTimeInterval(2_100),
                    attendees: [
                        UpcomingCalendarAttendee(
                            displayName: "Masha",
                            emailAddress: "masha@example.com"
                        ),
                        UpcomingCalendarAttendee(
                            displayName: "Ilya",
                            emailAddress: nil
                        ),
                    ]
                )
            ),
            dateProvider: { startedAt },
            meetingIDProvider: { meetingIDs.removeFirst() }
        )

        await viewModel.startRecording()

        let persistedMeeting = try #require(try harness.context.fetch(FetchDescriptor<Meeting>()).first)
        #expect(persistedMeeting.title == "Design Review")
        #expect(persistedMeeting.attendeeNames == ["Masha", "Ilya"])
    }

    @Test
    func startRecordingFallsBackToTimestampWhenCalendarMatchIsUnavailable() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_746_692_100)
        var meetingIDs = [meetingID]
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            calendarIntegration: StubCalendarIntegration(matchingEvent: nil),
            dateProvider: { startedAt },
            meetingIDProvider: { meetingIDs.removeFirst() },
            meetingTitleFormatter: formatter
        )

        await viewModel.startRecording()

        let persistedMeeting = try #require(try harness.context.fetch(FetchDescriptor<Meeting>()).first)
        #expect(persistedMeeting.title == formatter.string(from: startedAt))
    }

    @Test
    func startRecordingPersistsEmptyAttendeeNamesWithoutCalendarMatch() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_746_692_100)
        var meetingIDs = [meetingID]
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            calendarIntegration: StubCalendarIntegration(matchingEvent: nil),
            dateProvider: { startedAt },
            meetingIDProvider: { meetingIDs.removeFirst() },
            meetingTitleFormatter: formatter
        )

        await viewModel.startRecording()

        let persistedMeeting = try #require(try harness.context.fetch(FetchDescriptor<Meeting>()).first)
        #expect(persistedMeeting.title == formatter.string(from: startedAt))
        #expect(persistedMeeting.attendeeNames.isEmpty)
    }

    @Test
    func transcriptionProgressForMeetingReturnsLiveValue() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let viewModel = harness.makeViewModel()

        harness.progressCenter.startTracking(meetingID: meetingID)
        harness.progressCenter.updateProgress(0.48, for: meetingID)

        #expect(viewModel.transcriptionProgress(for: meetingID) == 0.48)
    }

    @Test
    func transcriptionProgressUpdatesNotifyObservedViews() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        let viewModel = harness.makeViewModel()
        var changeCount = 0

        harness.progressCenter.startTracking(meetingID: meetingID)

        let cancellable = viewModel.objectWillChange.sink {
            changeCount += 1
        }
        defer { cancellable.cancel() }

        harness.progressCenter.updateProgress(0.48, for: meetingID)

        #expect(changeCount == 1)
    }

    @Test
    func canTranscribeMeetingReturnsTrueForCompletedMeeting() async throws {
        let harness = try AppViewModelTestHarness()
        let meeting = try harness.createCompletedMeeting()
        let viewModel = harness.makeViewModel()

        #expect(viewModel.canTranscribeMeeting(meeting))
    }

    @Test
    func renameSpeakerDelegatesToTranscriptStoreAndClearsPreviousError() async throws {
        let harness = try AppViewModelTestHarness()
        let meeting = try harness.createCompletedMeetingWithTranscript()
        let viewModel = harness.makeViewModel()

        try await viewModel.renameSpeaker(
            meetingID: meeting.id,
            speakerID: "speaker-1",
            displayName: "Masha"
        )

        let snapshot = harness.meetingTranscriptStore.snapshot()
        #expect(snapshot.renames.count == 1)
        #expect(snapshot.renames.first?.meetingID == meeting.id)
        #expect(snapshot.renames.first?.speakerID == "speaker-1")
        #expect(snapshot.renames.first?.displayName == "Masha")
        #expect(viewModel.renameSpeakerErrorMessage == nil)
    }

    @Test
    func renameSpeakerStoresTheFailureMessageForUI() async throws {
        let harness = try AppViewModelTestHarness(
            renameResults: [.failure(MeetingTranscriptActionTestError.failed)]
        )
        let meeting = try harness.createCompletedMeetingWithTranscript()
        let viewModel = harness.makeViewModel()

        await #expect(throws: MeetingTranscriptActionTestError.failed) {
            try await viewModel.renameSpeaker(
                meetingID: meeting.id,
                speakerID: "speaker-1",
                displayName: "Masha"
            )
        }

        #expect(viewModel.renameSpeakerErrorMessage == "Speaker rename failed")
    }

    @Test
    func renameMeetingPersistsTitleAndClearsPreviousError() async throws {
        let harness = try AppViewModelTestHarness()
        let meeting = try harness.createRecordedMeeting()
        let renamedAt = Date(timeIntervalSince1970: 1_234_568_300)
        let invalidRenameViewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            dateProvider: { renamedAt }
        )

        await #expect(throws: MeetingStoreError.invalidMeetingTitle) {
            try await invalidRenameViewModel.renameMeeting(meeting, title: "   ")
        }

        let validRenameViewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            dateProvider: { renamedAt.addingTimeInterval(60) }
        )

        try await validRenameViewModel.renameMeeting(meeting, title: "Renamed Review")

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(reloaded.title == "Renamed Review")
        #expect(validRenameViewModel.renameMeetingErrorMessage == nil)
    }

    @Test
    func renameMeetingStoresTheFailureMessageForUI() async throws {
        let harness = try AppViewModelTestHarness()
        let meeting = try harness.createRecordedMeeting()
        let viewModel = harness.makeViewModel()

        await #expect(throws: MeetingStoreError.invalidMeetingTitle) {
            try await viewModel.renameMeeting(meeting, title: "   ")
        }

        #expect(viewModel.renameMeetingErrorMessage == "Meeting title cannot be empty.")
    }
}

@MainActor
struct MenuBarViewTests {
    @Test
    func primaryActionTitleTracksSharedRecordingState() async throws {
        let harness = try AppViewModelTestHarness()
        let meetingID = UUID()
        var meetingIDs = [meetingID]

        let viewModel = AppViewModel(
            meetingStore: harness.meetingStore,
            meetingFileStore: harness.meetingFileStore,
            recordingService: harness.recordingService,
            recordingPermissions: harness.recordingPermissions,
            meetingIDProvider: { meetingIDs.removeFirst() }
        )
        let view = MenuBarView(viewModel: viewModel)

        #expect(view.primaryActionTitle == "Start Recording")

        await view.performPrimaryAction()
        #expect(viewModel.recordingState == .recording(meetingID: meetingID))
        #expect(view.primaryActionTitle == "Stop Recording")

        await view.performPrimaryAction()
        #expect(viewModel.recordingState == .idle)
        #expect(view.primaryActionTitle == "Start Recording")
    }
}

@MainActor
struct DefaultRecordingServiceTests {
    @Test
    func startRecordingThrowsWhenARecordingIsAlreadyActive() async throws {
        let pipeline = AudioCapturePipelineSpy()
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)

        try await service.startRecording(
            meeting: makeMeeting(),
            outputURL: URL(fileURLWithPath: "/tmp/first-audio.wav")
        )

        await #expect(throws: DefaultRecordingServiceError.recordingAlreadyActive) {
            try await service.startRecording(
                meeting: makeMeeting(),
                outputURL: URL(fileURLWithPath: "/tmp/second-audio.wav")
            )
        }

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.startedOutputURLs == [URL(fileURLWithPath: "/tmp/first-audio.wav")])
    }

    @Test
    func stopRecordingStopsThePipelineAndClearsTheActiveRecording() async throws {
        let pipeline = AudioCapturePipelineSpy()
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)
        let firstOutputURL = URL(fileURLWithPath: "/tmp/first-audio.wav")
        let secondOutputURL = URL(fileURLWithPath: "/tmp/second-audio.wav")

        try await service.startRecording(meeting: makeMeeting(), outputURL: firstOutputURL)
        try await service.stopRecording()
        try await service.startRecording(meeting: makeMeeting(), outputURL: secondOutputURL)

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.startedOutputURLs == [firstOutputURL, secondOutputURL])
        #expect(snapshot.stopCallCount == 1)
    }

    @Test
    func startRecordingReturnsToIdleWhenPipelineStartThrows() async throws {
        let pipeline = AudioCapturePipelineSpy(
            startResults: [
                .failure(AudioCapturePipelineTestError.startFailed),
                .success(())
            ]
        )
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)
        let firstOutputURL = URL(fileURLWithPath: "/tmp/failed-audio.wav")
        let secondOutputURL = URL(fileURLWithPath: "/tmp/retry-audio.wav")

        await #expect(throws: AudioCapturePipelineTestError.startFailed) {
            try await service.startRecording(meeting: makeMeeting(), outputURL: firstOutputURL)
        }

        try await service.startRecording(meeting: makeMeeting(), outputURL: secondOutputURL)

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.startedOutputURLs == [firstOutputURL, secondOutputURL])
        #expect(snapshot.stopCallCount == 0)
    }

    @Test
    func stopRecordingCanBeRetriedWhenPipelineStopThrows() async throws {
        let pipeline = AudioCapturePipelineSpy(
            stopResults: [
                .failure(AudioCapturePipelineTestError.stopFailed),
                .success(())
            ]
        )
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)

        try await service.startRecording(
            meeting: makeMeeting(),
            outputURL: URL(fileURLWithPath: "/tmp/first-audio.wav")
        )

        await #expect(throws: AudioCapturePipelineTestError.stopFailed) {
            try await service.stopRecording()
        }

        await #expect(throws: DefaultRecordingServiceError.recordingAlreadyActive) {
            try await service.startRecording(
                meeting: makeMeeting(),
                outputURL: URL(fileURLWithPath: "/tmp/second-audio.wav")
            )
        }

        try await service.stopRecording()
        try await service.startRecording(
            meeting: makeMeeting(),
            outputURL: URL(fileURLWithPath: "/tmp/second-audio.wav")
        )

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.stopCallCount == 2)
    }

    @Test
    func stopRecordingDuringSuspendedStartWaitsForStartToFinishBeforeStopping() async throws {
        let pipeline = AudioCapturePipelineSpy(suspendNextStart: true)
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)
        let firstOutputURL = URL(fileURLWithPath: "/tmp/first-audio.wav")
        let secondOutputURL = URL(fileURLWithPath: "/tmp/second-audio.wav")

        let startTask = Task { @MainActor in
            try await service.startRecording(meeting: makeMeeting(), outputURL: firstOutputURL)
        }

        while await pipeline.snapshot().pendingStartCount == 0 {
            await Task.yield()
        }

        let stopTask = Task { @MainActor in
            try await service.stopRecording()
        }
        let duplicateStopTask = Task { @MainActor in
            try await service.stopRecording()
        }

        #expect(await pipeline.snapshot().stopCallCount == 0)

        await pipeline.resumeStart(with: .success(()))
        try await startTask.value
        try await stopTask.value
        try await duplicateStopTask.value

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.startCallCount == 1)
        #expect(snapshot.stopCallCount == 1)
        #expect(snapshot.startedOutputURLs == [firstOutputURL])

        try await service.startRecording(meeting: makeMeeting(), outputURL: secondOutputURL)
    }

    @Test
    func duplicateStopCallsShareTheSameSuspendedStopOperation() async throws {
        let pipeline = AudioCapturePipelineSpy(suspendNextStop: true)
        let service = DefaultRecordingService(audioCapturePipeline: pipeline)
        let firstOutputURL = URL(fileURLWithPath: "/tmp/first-audio.wav")
        let secondOutputURL = URL(fileURLWithPath: "/tmp/second-audio.wav")

        try await service.startRecording(meeting: makeMeeting(), outputURL: firstOutputURL)

        let firstStopTask = Task { @MainActor in
            try await service.stopRecording()
        }

        while await pipeline.snapshot().pendingStopCount == 0 {
            await Task.yield()
        }

        let duplicateStopTask = Task { @MainActor in
            try await service.stopRecording()
        }

        #expect(await pipeline.snapshot().stopCallCount == 1)

        await pipeline.resumeStop(with: .success(()))
        try await firstStopTask.value
        try await duplicateStopTask.value

        try await service.startRecording(meeting: makeMeeting(), outputURL: secondOutputURL)

        let snapshot = await pipeline.snapshot()
        #expect(snapshot.stopCallCount == 1)
        #expect(snapshot.startedOutputURLs == [firstOutputURL, secondOutputURL])
    }

    private func makeMeeting() -> Meeting {
        Meeting(
            title: "Test Meeting",
            startedAt: Date(timeIntervalSince1970: 1_234_567_890),
            status: .recording,
            audioFilePath: "/tmp/audio.wav"
        )
    }
}

@MainActor
struct NativeAudioCapturePipelineTests {
    @Test
    func startBuildsSystemAudioOnlySessionWithCanonicalWriterSettings() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-audio.wav")
        let session = AudioCaptureStreamSessionSpy()
        let writer = AudioFileWriterSpy()
        var requestedConfiguration: NativeAudioCapturePipeline.CaptureConfiguration?

        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) {
                    configuration,
                    _
                in
                    requestedConfiguration = configuration
                    return session
                }
            },
            writerFactory: { requestedURL in
                writer.createdOutputURLs.append(requestedURL)
                return writer
            },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration()
        )

        try await pipeline.start(outputURL: outputURL)
        try await pipeline.stop()

        #expect(writer.createdOutputURLs == [outputURL])
        #expect(writer.finishCallCount == 1)
        #expect(session.startCallCount == 1)
        #expect(session.stopCallCount == 1)
        #expect(
            requestedConfiguration == NativeAudioCapturePipeline.CaptureConfiguration(
                sampleRate: 48_000,
                channelCount: 2,
                capturesSystemAudio: true,
                capturesMicrophone: false
            )
        )
    }

    @Test
    func stopKeepsCaptureStateAliveWhenNativeStopFailsAndAllowsRetry() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-retry-stop.wav")
        let session = AudioCaptureStreamSessionSpy(suspendNextStop: true)
        let writer = AudioFileWriterSpy()

        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) { _, _ in
                    session
                }
            },
            writerFactory: { _ in writer },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration()
        )

        try await pipeline.start(outputURL: outputURL)

        let firstStopTask = Task { @MainActor in
            try await pipeline.stop()
        }

        while session.pendingStopCount == 0 {
            await Task.yield()
        }

        session.resumeStop(with: .failure(AudioCapturePipelineTestError.stopFailed))

        await #expect(throws: AudioCapturePipelineTestError.stopFailed) {
            try await firstStopTask.value
        }

        #expect(session.stopCallCount == 1)
        #expect(writer.finishCallCount == 0)

        try await pipeline.stop()

        #expect(session.stopCallCount == 2)
        #expect(writer.finishCallCount == 1)
    }

    @Test
    func startFailureFinalizesWriterExactlyOnce() async throws {
        let session = AudioCaptureStreamSessionSpy(
            startResults: [.failure(AudioCapturePipelineTestError.startFailed)]
        )
        let writer = AudioFileWriterSpy()
        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) { _, _ in
                    session
                }
            },
            writerFactory: { _ in writer },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration()
        )

        await #expect(throws: AudioCapturePipelineTestError.startFailed) {
            try await pipeline.start(outputURL: URL(fileURLWithPath: "/tmp/native-pipeline-start-failure.wav"))
        }

        #expect(session.startCallCount == 1)
        #expect(writer.finishCallCount == 1)
    }

    @Test
    func stopEmitsDiagnosticsForMissingOutputAndZeroSamples() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-missing-output.wav")
        let session = AudioCaptureStreamSessionSpy()
        let writer = AudioFileWriterSpy()
        let diagnosticRecorder = RecordingDiagnosticRecorder()

        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) { _, _ in
                    session
                }
            },
            writerFactory: { _ in writer },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration(),
            diagnosticHandler: { diagnosticRecorder.record($0) }
        )

        try await pipeline.start(outputURL: outputURL)
        try await pipeline.stop()

        let recordedDiagnostics = diagnosticRecorder.diagnostics
        let stopDiagnostics = try #require(
            recordedDiagnostics.last(where: { $0.event == .captureStopped })
        )
        #expect(stopDiagnostics.outputURL == outputURL)
        #expect(stopDiagnostics.sampleBufferCount == 0)
        #expect(stopDiagnostics.systemSampleBufferCount == 0)
        #expect(stopDiagnostics.microphoneSampleBufferCount == 0)
        #expect(stopDiagnostics.fileExists == false)
        #expect(stopDiagnostics.fileSizeBytes == nil)
        #expect(stopDiagnostics.errorDescription == nil)
    }

    @Test
    func stopEmitsPerSourceSampleCountsInDiagnostics() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-source-counts.wav")
        let session = AudioCaptureStreamSessionSpy()
        let writer = AudioFileWriterSpy()
        let diagnosticRecorder = RecordingDiagnosticRecorder()
        var createdSink: CaptureOutputSink?

        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) { _, sink in
                    createdSink = sink
                    return session
                }
            },
            writerFactory: { _ in writer },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration(
                capturesSystemAudio: true,
                capturesMicrophone: true
            ),
            diagnosticHandler: { diagnosticRecorder.record($0) }
        )

        try await pipeline.start(outputURL: outputURL)

        let sink = try #require(createdSink)
        try sink.appendForTesting(
            makeTestPCMBuffer(
                leftChannel: [0.10, 0.10],
                rightChannel: [0.10, 0.10]
            ),
            presentationTimeSeconds: 0,
            outputType: .audio
        )
        try sink.appendForTesting(
            makeTestPCMBuffer(
                leftChannel: [0.20, 0.20],
                rightChannel: [0.20, 0.20]
            ),
            presentationTimeSeconds: 0,
            outputType: .microphone
        )

        try await pipeline.stop()

        let recordedDiagnostics = diagnosticRecorder.diagnostics
        let stopDiagnostics = try #require(
            recordedDiagnostics.last(where: { $0.event == .captureStopped })
        )
        #expect(stopDiagnostics.sampleBufferCount == 2)
        #expect(stopDiagnostics.systemSampleBufferCount == 1)
        #expect(stopDiagnostics.microphoneSampleBufferCount == 1)
        #expect(stopDiagnostics.systemSourceFormat == "sampleRate=48000.0 channelCount=2 commonFormat=pcmFormatFloat32 interleaved=false")
        #expect(stopDiagnostics.microphoneSourceFormat == "sampleRate=48000.0 channelCount=2 commonFormat=pcmFormatFloat32 interleaved=false")
        #expect(stopDiagnostics.systemRawPeakPower == 0.10)
        #expect(stopDiagnostics.microphoneRawPeakPower == 0.20)
        #expect(stopDiagnostics.systemPeakPower == 0.10)
        #expect(stopDiagnostics.microphonePeakPower == 0.20)
        #expect(stopDiagnostics.writtenPeakPower == 0.30)
        #expect(stopDiagnostics.systemRawNonZeroFrameCount == 2)
        #expect(stopDiagnostics.microphoneRawNonZeroFrameCount == 2)
        #expect(stopDiagnostics.systemNonZeroFrameCount == 4)
        #expect(stopDiagnostics.microphoneNonZeroFrameCount == 4)
        #expect(stopDiagnostics.writtenNonZeroFrameCount == 2)
    }

    @Test
    func startBuildsSessionWithPinnedDefaultMicrophoneDeviceID() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-mic-device.wav")
        let session = AudioCaptureStreamSessionSpy()
        let writer = AudioFileWriterSpy()
        var requestedConfiguration: NativeAudioCapturePipeline.CaptureConfiguration?

        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) {
                    configuration,
                    _
                in
                    requestedConfiguration = configuration
                    return session
                }
            },
            writerFactory: { _ in writer },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration(
                capturesSystemAudio: true,
                capturesMicrophone: true
            ),
            microphoneDeviceProvider: {
                NativeAudioCapturePipeline.MicrophoneDevice(
                    id: "built-in-mic",
                    name: "Built-in Microphone"
                )
            }
        )

        try await pipeline.start(outputURL: outputURL)
        try await pipeline.stop()

        let configuration = try #require(requestedConfiguration)
        #expect(configuration.capturesMicrophone == true)
        #expect(configuration.microphoneCaptureDeviceID == "built-in-mic")
    }

    @Test
    func writerPreparedDiagnosticsIncludePinnedMicrophoneDeviceDetails() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-mic-diagnostics.wav")
        let session = AudioCaptureStreamSessionSpy()
        let writer = AudioFileWriterSpy()
        let diagnosticRecorder = RecordingDiagnosticRecorder()

        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) { _, _ in
                    session
                }
            },
            writerFactory: { _ in writer },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration(
                capturesSystemAudio: true,
                capturesMicrophone: true
            ),
            microphoneDeviceProvider: {
                NativeAudioCapturePipeline.MicrophoneDevice(
                    id: "built-in-mic",
                    name: "Built-in Microphone"
                )
            },
            diagnosticHandler: { diagnosticRecorder.record($0) }
        )

        try await pipeline.start(outputURL: outputURL)
        try await pipeline.stop()

        let recordedDiagnostics = diagnosticRecorder.diagnostics
        let preparedDiagnostics = try #require(
            recordedDiagnostics.first(where: { $0.event == .writerPrepared })
        )
        #expect(preparedDiagnostics.microphoneCaptureDeviceID == "built-in-mic")
        #expect(preparedDiagnostics.microphoneCaptureDeviceName == "Built-in Microphone")
        #expect(preparedDiagnostics.systemSourceFormat == nil)
        #expect(preparedDiagnostics.microphoneSourceFormat == nil)
        #expect(preparedDiagnostics.systemRawPeakPower == 0)
        #expect(preparedDiagnostics.microphoneRawPeakPower == 0)
        #expect(preparedDiagnostics.systemPeakPower == 0)
        #expect(preparedDiagnostics.microphonePeakPower == 0)
        #expect(preparedDiagnostics.writtenPeakPower == 0)
    }

    @Test
    func stopEmitsZeroEnergyForSilentBuffers() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-silent-diagnostics.wav")
        let session = AudioCaptureStreamSessionSpy()
        let writer = AudioFileWriterSpy()
        let diagnosticRecorder = RecordingDiagnosticRecorder()
        var createdSink: CaptureOutputSink?

        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) { _, sink in
                    createdSink = sink
                    return session
                }
            },
            writerFactory: { _ in writer },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration(
                capturesSystemAudio: true,
                capturesMicrophone: true
            ),
            diagnosticHandler: { diagnosticRecorder.record($0) }
        )

        try await pipeline.start(outputURL: outputURL)

        let sink = try #require(createdSink)
        try sink.appendForTesting(
            makeTestPCMBuffer(
                leftChannel: [0, 0],
                rightChannel: [0, 0]
            ),
            presentationTimeSeconds: 0,
            outputType: .audio
        )
        try sink.appendForTesting(
            makeTestPCMBuffer(
                leftChannel: [0, 0],
                rightChannel: [0, 0]
            ),
            presentationTimeSeconds: 0,
            outputType: .microphone
        )

        try await pipeline.stop()

        let recordedDiagnostics = diagnosticRecorder.diagnostics
        let stopDiagnostics = try #require(
            recordedDiagnostics.last(where: { $0.event == .captureStopped })
        )
        #expect(stopDiagnostics.systemRawPeakPower == 0)
        #expect(stopDiagnostics.microphoneRawPeakPower == 0)
        #expect(stopDiagnostics.systemPeakPower == 0)
        #expect(stopDiagnostics.microphonePeakPower == 0)
        #expect(stopDiagnostics.writtenPeakPower == 0)
        #expect(stopDiagnostics.systemRawRMSPower == 0)
        #expect(stopDiagnostics.microphoneRawRMSPower == 0)
        #expect(stopDiagnostics.systemRMSPower == 0)
        #expect(stopDiagnostics.microphoneRMSPower == 0)
        #expect(stopDiagnostics.writtenRMSPower == 0)
        #expect(stopDiagnostics.systemRawNonZeroFrameCount == 0)
        #expect(stopDiagnostics.microphoneRawNonZeroFrameCount == 0)
        #expect(stopDiagnostics.systemNonZeroFrameCount == 0)
        #expect(stopDiagnostics.microphoneNonZeroFrameCount == 0)
        #expect(stopDiagnostics.writtenNonZeroFrameCount == 0)
    }

    @Test
    func stopEmitsRawMetricsBeforeCanonicalConversion() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-raw-diagnostics.wav")
        let session = AudioCaptureStreamSessionSpy()
        let writer = AudioFileWriterSpy()
        let diagnosticRecorder = RecordingDiagnosticRecorder()
        var createdSink: CaptureOutputSink?

        let pipeline = NativeAudioCapturePipeline(
            shareableContentProvider: {
                NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) { _, sink in
                    createdSink = sink
                    return session
                }
            },
            writerFactory: { _ in writer },
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration(
                capturesSystemAudio: true,
                capturesMicrophone: true
            ),
            diagnosticHandler: { diagnosticRecorder.record($0) }
        )

        try await pipeline.start(outputURL: outputURL)

        let sink = try #require(createdSink)
        try sink.appendForTesting(
            makeMonoTestPCMBuffer(samples: [0.10, 0.10], sampleRate: 16_000),
            presentationTimeSeconds: 0,
            outputType: .audio
        )
        try sink.appendForTesting(
            makeMonoTestPCMBuffer(samples: [0.20, 0.20], sampleRate: 16_000),
            presentationTimeSeconds: 0,
            outputType: .microphone
        )

        try await pipeline.stop()

        let recordedDiagnostics = diagnosticRecorder.diagnostics
        let stopDiagnostics = try #require(
            recordedDiagnostics.last(where: { $0.event == .captureStopped })
        )
        #expect(stopDiagnostics.systemSourceFormat == "sampleRate=16000.0 channelCount=1 commonFormat=pcmFormatFloat32 interleaved=false")
        #expect(stopDiagnostics.microphoneSourceFormat == "sampleRate=16000.0 channelCount=1 commonFormat=pcmFormatFloat32 interleaved=false")
        #expect(stopDiagnostics.systemRawPeakPower == 0.10)
        #expect(stopDiagnostics.microphoneRawPeakPower == 0.20)
        #expect(stopDiagnostics.systemRawNonZeroFrameCount == 2)
        #expect(stopDiagnostics.microphoneRawNonZeroFrameCount == 2)
        #expect(stopDiagnostics.systemPeakPower == 0.10)
        #expect(stopDiagnostics.microphonePeakPower == 0.20)
        #expect(stopDiagnostics.writtenPeakPower == 0.30)
    }

    @Test
    func captureOutputSinkMixesSystemAndMicrophoneAudioIntoSingleWriterStream() async throws {
        let writer = AudioFileWriterSpy()
        let sink = CaptureOutputSink(
            writer: writer,
            captureConfiguration: .init(capturesMicrophone: true)
        )

        try sink.appendForTesting(
            makeTestPCMBuffer(
                leftChannel: [0.25, 0.25],
                rightChannel: [0.25, 0.25]
            ),
            presentationTimeSeconds: 0,
            outputType: .audio
        )
        try sink.appendForTesting(
            makeTestPCMBuffer(
                leftChannel: [0.50, 0.50],
                rightChannel: [0.50, 0.50]
            ),
            presentationTimeSeconds: 0,
            outputType: .microphone
        )

        _ = try await sink.finish()

        #expect(writer.finishCallCount == 1)
        #expect(writer.appendedBuffers.count == 1)

        let mixedBuffer = try #require(writer.appendedBuffers.first)
        #expect(mixedBuffer.frameLength == 2)
        #expect(mixedBuffer.floatChannelData?[0][0] == 0.75)
        #expect(mixedBuffer.floatChannelData?[0][1] == 0.75)
        #expect(mixedBuffer.floatChannelData?[1][0] == 0.75)
        #expect(mixedBuffer.floatChannelData?[1][1] == 0.75)
    }

    @Test
    func captureOutputSinkMixesSlightlyOffsetSystemAndMicrophoneBuffersIntoSingleWriterStream() async throws {
        let writer = AudioFileWriterSpy()
        let sink = CaptureOutputSink(
            writer: writer,
            captureConfiguration: .init(capturesMicrophone: true)
        )

        try sink.appendForTesting(
            makeTestPCMBuffer(
                leftChannel: [0.20, 0.20],
                rightChannel: [0.20, 0.20]
            ),
            presentationTimeSeconds: 1.000,
            outputType: .audio
        )
        try sink.appendForTesting(
            makeTestPCMBuffer(
                leftChannel: [0.30, 0.30],
                rightChannel: [0.30, 0.30]
            ),
            presentationTimeSeconds: 1.005,
            outputType: .microphone
        )

        _ = try await sink.finish()

        #expect(writer.appendedBuffers.count == 1)
        let mixedBuffer = try #require(writer.appendedBuffers.first)
        #expect(mixedBuffer.floatChannelData?[0][0] == 0.50)
        #expect(mixedBuffer.floatChannelData?[1][0] == 0.50)
    }

    @Test
    func captureOutputSinkConvertsMicrophoneBufferFromDifferentInputFormat() async throws {
        let writer = AudioFileWriterSpy()
        let sink = CaptureOutputSink(
            writer: writer,
            captureConfiguration: .init(capturesMicrophone: true)
        )

        try sink.appendForTesting(
            makeTestPCMBuffer(
                leftChannel: [0.10, 0.10],
                rightChannel: [0.10, 0.10]
            ),
            presentationTimeSeconds: 2.000,
            outputType: .audio
        )
        try sink.appendForTesting(
            makeMonoTestPCMBuffer(
                samples: [0.40, 0.40],
                sampleRate: 44_100
            ),
            presentationTimeSeconds: 2.005,
            outputType: .microphone
        )

        _ = try await sink.finish()

        #expect(writer.appendedBuffers.count == 1)
        let mixedBuffer = try #require(writer.appendedBuffers.first)
        #expect(mixedBuffer.frameLength > 0)
        #expect((mixedBuffer.floatChannelData?[0][0] ?? 0) > 0.10)
        #expect((mixedBuffer.floatChannelData?[1][0] ?? 0) > 0.10)
    }

    @Test
    func captureOutputSinkConvertsInterleavedMonoMicrophoneBufferWithoutSilencingIt() async throws {
        let writer = AudioFileWriterSpy()
        let sink = CaptureOutputSink(
            writer: writer,
            captureConfiguration: .init(capturesMicrophone: true)
        )

        try sink.appendForTesting(
            makePCMBufferFromSampleBufferForTesting(
                makeInterleavedMonoAudioSampleBuffer(
                    samples: [0.30, -0.15, 0.25, -0.10],
                    sampleRate: 24_000,
                    presentationTimeSeconds: 4.000
                )
            ),
            presentationTimeSeconds: 4.000,
            outputType: .microphone
        )

        let diagnostics = try await sink.finish()

        #expect(diagnostics.microphoneSourceFormat == "sampleRate=24000.0 channelCount=1 commonFormat=pcmFormatFloat32 interleaved=true")
        #expect(diagnostics.microphoneRawMetrics.peakPower == 0.30)
        #expect(diagnostics.microphoneRawMetrics.nonZeroFrameCount == 4)
        #expect(diagnostics.microphoneMetrics.peakPower > 0)
        #expect(diagnostics.microphoneMetrics.nonZeroFrameCount > 0)
        #expect(diagnostics.writtenMetrics.peakPower > 0)

        #expect(writer.appendedBuffers.count == 1)
        let mixedBuffer = try #require(writer.appendedBuffers.first)
        #expect(mixedBuffer.frameLength > 0)
        #expect(abs(mixedBuffer.floatChannelData?[0][0] ?? 0) > 0)
        #expect(abs(mixedBuffer.floatChannelData?[1][0] ?? 0) > 0)
    }

    @Test
    func captureOutputSinkConvertsDirectInterleavedMonoMicrophoneBufferWithoutSilencingIt() async throws {
        let writer = AudioFileWriterSpy()
        let sink = CaptureOutputSink(
            writer: writer,
            captureConfiguration: .init(capturesMicrophone: true)
        )

        try sink.appendForTesting(
            makeInterleavedMonoTestPCMBuffer(
                samples: [0.30, -0.15, 0.25, -0.10],
                sampleRate: 24_000
            ),
            presentationTimeSeconds: 4.000,
            outputType: .microphone
        )

        let diagnostics = try await sink.finish()

        #expect(diagnostics.microphoneSourceFormat == "sampleRate=24000.0 channelCount=1 commonFormat=pcmFormatFloat32 interleaved=true")
        #expect(diagnostics.microphoneRawMetrics.peakPower == 0.30)
        #expect(diagnostics.microphoneRawMetrics.nonZeroFrameCount == 4)
        #expect(diagnostics.microphoneMetrics.peakPower > 0)
        #expect(diagnostics.microphoneMetrics.nonZeroFrameCount > 0)
        #expect(diagnostics.writtenMetrics.peakPower > 0)

        #expect(writer.appendedBuffers.count == 1)
    }

    @Test
    func captureOutputSinkPreservesLongerSystemBufferTailAfterMixing() async throws {
        let writer = AudioFileWriterSpy()
        let sink = CaptureOutputSink(
            writer: writer,
            captureConfiguration: .init(capturesMicrophone: true)
        )

        try sink.appendForTesting(
            makeTestPCMBuffer(
                leftChannel: [0.20, 0.20, 0.20, 0.20],
                rightChannel: [0.20, 0.20, 0.20, 0.20]
            ),
            presentationTimeSeconds: 3.000,
            outputType: .audio
        )
        try sink.appendForTesting(
            makeTestPCMBuffer(
                leftChannel: [0.30, 0.30],
                rightChannel: [0.30, 0.30]
            ),
            presentationTimeSeconds: 3.000,
            outputType: .microphone
        )

        _ = try await sink.finish()

        #expect(writer.appendedBuffers.count == 2)

        let mixedPrefix = try #require(writer.appendedBuffers.first)
        #expect(mixedPrefix.frameLength == 2)
        #expect(mixedPrefix.floatChannelData?[0][0] == 0.50)

        let preservedTail = try #require(writer.appendedBuffers.last)
        #expect(preservedTail.frameLength == 2)
        #expect(preservedTail.floatChannelData?[0][0] == 0.20)
        #expect(preservedTail.floatChannelData?[1][0] == 0.20)
    }

    private func makeTestPCMBuffer(
        leftChannel: [Float],
        rightChannel: [Float]
    ) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )
        )
        let frameCount = min(leftChannel.count, rightChannel.count)
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )

        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channelData = try #require(buffer.floatChannelData)

        for index in 0 ..< frameCount {
            channelData[0][index] = leftChannel[index]
            channelData[1][index] = rightChannel[index]
        }

        return buffer
    }

    private func makeMonoTestPCMBuffer(
        samples: [Float],
        sampleRate: Double
    ) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        )

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = try #require(buffer.floatChannelData)

        for index in 0 ..< samples.count {
            channelData[0][index] = samples[index]
        }

        return buffer
    }

    private func makeInterleavedMonoTestPCMBuffer(
        samples: [Float],
        sampleRate: Double
    ) throws -> AVAudioPCMBuffer {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: true
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        )

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let audioBuffer = try #require(audioBuffers.first)
        let channelData = try #require(audioBuffer.mData?.assumingMemoryBound(to: Float.self))

        for index in 0 ..< samples.count {
            channelData[index] = samples[index]
        }

        return buffer
    }

    private func makeInterleavedMonoAudioSampleBuffer(
        samples: [Float],
        sampleRate: Double,
        presentationTimeSeconds: Double
    ) throws -> CMSampleBuffer {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.stride),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.stride),
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw NativeAudioCapturePipelineError.audioConversionFailed
        }

        let byteCount = samples.count * MemoryLayout<Float>.stride
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
            throw NativeAudioCapturePipelineError.audioBufferCopyFailed(blockStatus)
        }

        let replaceStatus = samples.withUnsafeBytes { sampleBytes in
            CMBlockBufferReplaceDataBytes(
                with: sampleBytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard replaceStatus == kCMBlockBufferNoErr else {
            throw NativeAudioCapturePipelineError.audioBufferCopyFailed(replaceStatus)
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: CMTime(seconds: presentationTimeSeconds, preferredTimescale: 48_000),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let sampleSize = byteCount / samples.count
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: samples.count,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: [sampleSize],
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw NativeAudioCapturePipelineError.audioBufferCopyFailed(sampleStatus)
        }

        return sampleBuffer
    }

    private func makePCMBufferFromSampleBufferForTesting(
        _ sampleBuffer: CMSampleBuffer
    ) throws -> AVAudioPCMBuffer {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)

        guard frameCount > 0,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let pcmBuffer = AVAudioPCMBuffer(
                  pcmFormat: AVAudioFormat(cmAudioFormatDescription: formatDescription),
                  frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            throw NativeAudioCapturePipelineError.invalidAudioSampleBuffer
        }

        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw NativeAudioCapturePipelineError.audioBufferCopyFailed(status)
        }

        return pcmBuffer
    }
}

private final class RecordingDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDiagnostics: [NativeAudioCapturePipeline.RecordingDiagnostics] = []

    func record(_ diagnostic: NativeAudioCapturePipeline.RecordingDiagnostics) {
        lock.lock()
        storedDiagnostics.append(diagnostic)
        lock.unlock()
    }

    var diagnostics: [NativeAudioCapturePipeline.RecordingDiagnostics] {
        lock.lock()
        let diagnostics = storedDiagnostics
        lock.unlock()
        return diagnostics
    }
}

@MainActor
private final class RecordingServiceSpy: RecordingService {
    private var queuedStartResults: [Result<Void, Error>]
    private var queuedStopResults: [Result<Void, Error>]
    private(set) var startAttempts: [StartAttempt] = []
    private(set) var stopAttempts = 0

    init(
        queuedResults: [Result<Void, Error>] = [.success(())],
        stopResults: [Result<Void, Error>] = [.success(())]
    ) {
        queuedStartResults = queuedResults
        queuedStopResults = stopResults
    }

    func startRecording(meeting: Meeting, outputURL: URL) async throws {
        startAttempts.append(StartAttempt(meetingID: meeting.id, outputURL: outputURL))
        let nextResult = queuedStartResults.isEmpty ? .success(()) : queuedStartResults.removeFirst()
        try nextResult.get()
    }

    func stopRecording() async throws {
        stopAttempts += 1
        let nextResult = queuedStopResults.isEmpty ? .success(()) : queuedStopResults.removeFirst()
        try nextResult.get()
    }

    func snapshot() -> Snapshot {
        Snapshot(startAttempts: startAttempts, stopAttempts: stopAttempts)
    }
}

private actor AudioCapturePipelineSpy: AudioCapturePipeline {
    private var startResults: [Result<Void, Error>]
    private var stopResults: [Result<Void, Error>]
    private var suspendNextStart: Bool
    private var suspendNextStop: Bool
    private var pendingStartContinuations: [CheckedContinuation<Result<Void, Error>, Never>] = []
    private var pendingStopContinuations: [CheckedContinuation<Result<Void, Error>, Never>] = []
    private var startedOutputURLs: [URL] = []
    private var startCallCount = 0
    private var stopCallCount = 0

    init(
        startResults: [Result<Void, Error>] = [.success(())],
        stopResults: [Result<Void, Error>] = [.success(())],
        suspendNextStart: Bool = false,
        suspendNextStop: Bool = false
    ) {
        self.startResults = startResults
        self.stopResults = stopResults
        self.suspendNextStart = suspendNextStart
        self.suspendNextStop = suspendNextStop
    }

    func start(outputURL: URL) async throws {
        startCallCount += 1
        startedOutputURLs.append(outputURL)

        if suspendNextStart {
            suspendNextStart = false
            let result = await withCheckedContinuation { continuation in
                pendingStartContinuations.append(continuation)
            }
            try result.get()
            return
        }

        let result = startResults.isEmpty ? .success(()) : startResults.removeFirst()
        try result.get()
    }

    func stop() async throws {
        stopCallCount += 1

        if suspendNextStop {
            suspendNextStop = false
            let result = await withCheckedContinuation { continuation in
                pendingStopContinuations.append(continuation)
            }
            try result.get()
            return
        }

        let result = stopResults.isEmpty ? .success(()) : stopResults.removeFirst()
        try result.get()
    }

    func resumeStart(with result: Result<Void, Error>) {
        guard !pendingStartContinuations.isEmpty else {
            return
        }

        let continuation = pendingStartContinuations.removeFirst()
        continuation.resume(returning: result)
    }

    func resumeStop(with result: Result<Void, Error>) {
        guard !pendingStopContinuations.isEmpty else {
            return
        }

        let continuation = pendingStopContinuations.removeFirst()
        continuation.resume(returning: result)
    }

    func snapshot() async -> AudioCapturePipelineSnapshot {
        AudioCapturePipelineSnapshot(
            startedOutputURLs: startedOutputURLs,
            startCallCount: startCallCount,
            stopCallCount: stopCallCount,
            pendingStartCount: pendingStartContinuations.count,
            pendingStopCount: pendingStopContinuations.count
        )
    }
}

private final class AudioCaptureStreamSessionSpy: NativeAudioCapturePipeline.AudioCaptureStreamSession {
    private let startResults: [Result<Void, Error>]
    private var nextStartResultIndex = 0
    private let stopResults: [Result<Void, Error>]
    private var nextStopResultIndex = 0
    private var suspendNextStart: Bool
    private var suspendNextStop: Bool
    private var pendingStartContinuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var pendingStopContinuation: CheckedContinuation<Result<Void, Error>, Never>?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    var pendingStartCount: Int { pendingStartContinuation == nil ? 0 : 1 }
    var pendingStopCount: Int { pendingStopContinuation == nil ? 0 : 1 }

    init(
        startResults: [Result<Void, Error>] = [.success(())],
        stopResults: [Result<Void, Error>] = [.success(())],
        suspendNextStart: Bool = false,
        suspendNextStop: Bool = false
    ) {
        self.startResults = startResults
        self.stopResults = stopResults
        self.suspendNextStart = suspendNextStart
        self.suspendNextStop = suspendNextStop
    }

    func start() async throws {
        startCallCount += 1

        if suspendNextStart {
            suspendNextStart = false
            let result = await withCheckedContinuation { continuation in
                pendingStartContinuation = continuation
            }
            try result.get()
            return
        }

        let result = nextStartResult()
        try result.get()
    }

    func stop() async throws {
        stopCallCount += 1

        if suspendNextStop {
            suspendNextStop = false
            let result = await withCheckedContinuation { continuation in
                pendingStopContinuation = continuation
            }
            try result.get()
            return
        }

        let result = nextStopResult()
        try result.get()
    }

    func resumeStart(with result: Result<Void, Error>) {
        pendingStartContinuation?.resume(returning: result)
        pendingStartContinuation = nil
    }

    func resumeStop(with result: Result<Void, Error>) {
        pendingStopContinuation?.resume(returning: result)
        pendingStopContinuation = nil
    }

    private func nextStartResult() -> Result<Void, Error> {
        guard nextStartResultIndex < startResults.count else {
            return .success(())
        }

        defer { nextStartResultIndex += 1 }
        return startResults[nextStartResultIndex]
    }

    private func nextStopResult() -> Result<Void, Error> {
        guard nextStopResultIndex < stopResults.count else {
            return .success(())
        }

        defer { nextStopResultIndex += 1 }
        return stopResults[nextStopResultIndex]
    }
}

private final class AudioFileWriterSpy: NativeAudioCapturePipeline.AudioFileWriting {
    var createdOutputURLs: [URL] = []
    private(set) var appendedBuffers: [AVAudioPCMBuffer] = []
    private(set) var finishCallCount = 0

    func append(_ buffer: AVAudioPCMBuffer) throws {
        appendedBuffers.append(buffer)
    }

    func finish() throws {
        finishCallCount += 1
    }
}

@MainActor
private struct AppViewModelTestHarness {
    let fileManager: FileManager
    let context: ModelContext
    let meetingStore: MeetingStore
    let meetingFileStore: MeetingFileStore
    let recordingService: RecordingServiceSpy
    let recordingPermissions: RecordingPermissionsSpy
    let transcriptionService: TranscriptionServiceSpy
    let meetingTranscriptStore: MeetingTranscriptStoreSpy
    let progressCenter: TranscriptionProgressCenter
    let rootURL: URL

    init(
        queuedResults: [Result<Void, Error>] = [.success(())],
        stopResults: [Result<Void, Error>] = [.success(())],
        permissionResult: RecordingPermissionResult = .granted,
        transcriptionResults: [Result<Void, Error>] = [.success(())],
        renameResults: [Result<Void, Error>] = [.success(())]
    ) throws {
        let schema = Schema([
            Meeting.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        self.fileManager = fileManager
        self.context = context
        self.meetingStore = MeetingStore(modelContext: context)
        self.meetingFileStore = MeetingFileStore(fileManager: fileManager, rootURL: rootURL)
        self.recordingService = RecordingServiceSpy(
            queuedResults: queuedResults,
            stopResults: stopResults
        )
        self.recordingPermissions = RecordingPermissionsSpy(result: permissionResult)
        self.transcriptionService = TranscriptionServiceSpy(queuedResults: transcriptionResults)
        self.meetingTranscriptStore = MeetingTranscriptStoreSpy(queuedResults: renameResults)
        self.progressCenter = TranscriptionProgressCenter()
        self.rootURL = rootURL
    }

    func artifactsURL(for meetingID: UUID) -> MeetingArtifacts {
        let meetingFolderURL = rootURL
            .appendingPathComponent(meetingID.uuidString, isDirectory: true)
        return MeetingArtifacts(
            meetingFolderURL: meetingFolderURL,
            audioFileURL: meetingFolderURL.appendingPathComponent("audio.wav")
        )
    }

    func createRecordedMeeting() throws -> Meeting {
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let artifacts = try meetingFileStore.createArtifacts(for: meetingID, startedAt: startedAt)
        fileManager.createFile(atPath: artifacts.audioFileURL.path, contents: Data("audio".utf8))
        let meeting = try meetingStore.createMeeting(
            id: meetingID,
            title: "Recorded Meeting",
            startedAt: startedAt,
            folderURL: artifacts.meetingFolderURL,
            audioFileURL: artifacts.audioFileURL
        )
        try meetingStore.finishRecording(meetingID: meeting.id, endedAt: startedAt.addingTimeInterval(60))
        return meeting
    }

    func createCompletedMeeting() throws -> Meeting {
        let meeting = try createRecordedMeeting()
        let transcriptURL = artifactsURL(for: meeting.id).meetingFolderURL.appendingPathComponent("transcript.md")
        try meetingStore.completeTranscription(
            meetingID: meeting.id,
            transcriptFileURL: transcriptURL,
            transcriptPreview: "Existing transcript",
            updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
        )
        return try meetingStore.fetchMeeting(id: meeting.id)
    }

    func createCompletedMeetingWithTranscript() throws -> Meeting {
        let meeting = try createRecordedMeeting()
        let meetingFolderURL = artifactsURL(for: meeting.id).meetingFolderURL
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello world", speakerID: "speaker-1")]
        )
        let artifacts = try TranscriptionArtifactWriter(fileManager: fileManager)
            .writeArtifacts(for: transcript, in: meetingFolderURL)
        try meetingStore.completeTranscription(
            meetingID: meeting.id,
            transcriptFileURL: artifacts.transcriptFileURL,
            transcriptPreview: artifacts.previewText,
            updatedAt: Date(timeIntervalSince1970: 1_234_568_150)
        )
        return try meetingStore.fetchMeeting(id: meeting.id)
    }

    func reloadMeeting(id: UUID) throws -> Meeting {
        try meetingStore.fetchMeeting(id: id)
    }

    func makeViewModel() -> AppViewModel {
        AppViewModel(
            meetingStore: meetingStore,
            meetingFileStore: meetingFileStore,
            recordingService: recordingService,
            transcriptionService: transcriptionService,
            transcriptionProgressCenter: progressCenter,
            recordingPermissions: recordingPermissions,
            meetingTranscriptStore: meetingTranscriptStore
        )
    }
}

private enum StartRecordingTestError: LocalizedError {
    case startFailed

    var errorDescription: String? {
        switch self {
        case .startFailed:
            "Recording startup failed"
        }
    }
}

private enum StopRecordingTestError: LocalizedError {
    case stopFailed

    var errorDescription: String? {
        switch self {
        case .stopFailed:
            "Recording shutdown failed"
        }
    }
}

private enum TranscriptionActionTestError: LocalizedError {
    case failed

    var errorDescription: String? {
        switch self {
        case .failed:
            "Transcription failed"
        }
    }
}

private enum MeetingTranscriptActionTestError: LocalizedError {
    case failed

    var errorDescription: String? {
        switch self {
        case .failed:
            "Speaker rename failed"
        }
    }
}

private struct Snapshot {
    let startAttempts: [StartAttempt]
    let stopAttempts: Int
}

private struct StartAttempt {
    let meetingID: UUID
    let outputURL: URL
}

@MainActor
private final class TranscriptionServiceSpy: TranscriptionServicing {
    private var queuedResults: [Result<Void, Error>]
    private var transcribedMeetingIDs = [UUID]()

    init(queuedResults: [Result<Void, Error>] = [.success(())]) {
        self.queuedResults = queuedResults
    }

    func transcribe(meetingID: UUID) async throws {
        transcribedMeetingIDs.append(meetingID)
        guard !queuedResults.isEmpty else {
            return
        }

        switch queuedResults.removeFirst() {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    func snapshot() -> TranscriptionServiceSnapshot {
        TranscriptionServiceSnapshot(transcribedMeetingIDs: transcribedMeetingIDs)
    }
}

private struct TranscriptionServiceSnapshot {
    let transcribedMeetingIDs: [UUID]
}

private struct RenameAttempt {
    let meetingID: UUID
    let speakerID: String
    let displayName: String
}

private struct MeetingTranscriptStoreSnapshot {
    let renames: [RenameAttempt]
}

@MainActor
private final class MeetingTranscriptStoreSpy: MeetingTranscriptStoring {
    private var queuedResults: [Result<Void, Error>]
    private var renames = [RenameAttempt]()

    init(queuedResults: [Result<Void, Error>] = [.success(())]) {
        self.queuedResults = queuedResults
    }

    @discardableResult
    func renameSpeaker(id: String, to displayName: String, in meetingFolderURL: URL) throws -> StoredTranscript {
        try renameSpeaker(id: id, to: displayName, in: UUID())
    }

    @discardableResult
    func renameSpeaker(id: String, to displayName: String, in meetingID: UUID) throws -> StoredTranscript {
        renames.append(
            RenameAttempt(
                meetingID: meetingID,
                speakerID: id,
                displayName: displayName
            )
        )

        if !queuedResults.isEmpty {
            switch queuedResults.removeFirst() {
            case .success:
                break
            case .failure(let error):
                throw error
            }
        }

        return StoredTranscript(
            speakers: [TranscriptSpeaker(id: id, displayName: displayName)],
            segments: [TranscriptSegment(text: "Hello world", speakerID: id)]
        )
    }

    func snapshot() -> MeetingTranscriptStoreSnapshot {
        MeetingTranscriptStoreSnapshot(renames: renames)
    }
}

@MainActor
private final class RecordingPermissionsSpy: RecordingPermissions {
    private let result: RecordingPermissionResult
    private(set) var ensurePermissionsCallCount = 0

    init(result: RecordingPermissionResult = .granted) {
        self.result = result
    }

    func ensurePermissions() async -> RecordingPermissionResult {
        ensurePermissionsCallCount += 1
        return result
    }

    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(ensurePermissionsCallCount: ensurePermissionsCallCount)
    }
}

private struct PermissionSnapshot {
    let ensurePermissionsCallCount: Int
}

private struct AudioCapturePipelineSnapshot {
    let startedOutputURLs: [URL]
    let startCallCount: Int
    let stopCallCount: Int
    let pendingStartCount: Int
    let pendingStopCount: Int
}

private struct StubCalendarIntegration: CalendarIntegration {
    var authorization: CalendarAuthorizationState = .authorized
    var calendars: [CalendarDescriptor] = []
    var upcomingEvent: UpcomingCalendarEvent?
    var matchingEvent: UpcomingCalendarEvent?

    func authorizationState() -> CalendarAuthorizationState {
        authorization
    }

    func requestAccess() async -> CalendarAuthorizationState {
        authorization
    }

    func availableCalendars() -> [CalendarDescriptor] {
        calendars
    }

    func upcomingEventForToday() -> UpcomingCalendarEvent? {
        upcomingEvent
    }

    func eventMatchingRecordingStart(at startedAt: Date) -> UpcomingCalendarEvent? {
        matchingEvent
    }
}

private enum AudioCapturePipelineTestError: LocalizedError {
    case startFailed
    case stopFailed

    var errorDescription: String? {
        switch self {
        case .startFailed:
            "Audio capture start failed"
        case .stopFailed:
            "Audio capture stop failed"
        }
    }
}

@MainActor
private final class SuspendedRecordingPermissionsSpy: RecordingPermissions {
    private var continuation: CheckedContinuation<RecordingPermissionResult, Never>?
    private(set) var ensurePermissionsCallCount = 0

    func ensurePermissions() async -> RecordingPermissionResult {
        ensurePermissionsCallCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: RecordingPermissionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
