//
//  AppViewModel.swift
//  QuickMeeting
//
//  Created by Codex on 04.05.2026.
//

import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var autoRecordingStatusText: String?
    @Published private(set) var isAutoRecordingStartPending = false
    @Published private(set) var recordingStartedAt: Date?
    @Published private(set) var activeRecordingTitle: String?
    @Published private(set) var autoRecordingDetectedAt: Date?
    @Published private(set) var deletionErrorMessage: String?
    @Published private(set) var transcriptionErrorMessage: String?
    @Published private var summaryError: SummaryErrorState?
    @Published private(set) var summaryConfirmationMeetingID: UUID?
    @Published private(set) var summarizingMeetingID: UUID?
    @Published private(set) var renameSpeakerErrorMessage: String?
    @Published private(set) var renameMeetingErrorMessage: String?
    @Published private(set) var calendarEventSelectionErrorMessage: String?
    @Published private(set) var upcomingCalendarEvent: UpcomingCalendarEvent?
    @Published private var calendarEventCandidatesByMeetingID: [UUID: [UpcomingCalendarEvent]] = [:]

    var summaryErrorMessage: String? {
        summaryError?.message
    }

    let transcriptionProgressCenter: TranscriptionProgressCenter
    private let meetingStore: MeetingStore
    private let meetingFileStore: MeetingFileStore
    private let recordingService: any RecordingService
    private let transcriptionService: any TranscriptionServicing
    private let meetingSummaryService: any MeetingSummaryServicing
    private let meetingSummarySettingsStore: any MeetingSummarySettingsStoring
    private let meetingTranscriptStore: any MeetingTranscriptStoring
    private let knownSpeakerEnrollmentService: (any KnownSpeakerEnrolling)?
    private let recordingPermissions: any RecordingPermissions
    private let calendarIntegration: any CalendarIntegration
    private let speakerSuggestionService: (any SpeakerSuggestionRecomputing)?
    private let screenObservationCapturer: (any MeetingScreenObservationCapturing)?
    private let dateProvider: () -> Date
    private let meetingIDProvider: () -> UUID
    private let meetingTitleFormatter: DateFormatter
    private var autoRecordingCoordinator: AutoRecordingCoordinator?
    private var recoverableRecordingMeetingID: UUID?
    private var pendingSummaryReplacementMeetingID: UUID?
    private var cancellables = Set<AnyCancellable>()

    init(
        meetingStore: MeetingStore,
        meetingFileStore: MeetingFileStore,
        recordingService: any RecordingService,
        transcriptionService: (any TranscriptionServicing)? = nil,
        meetingSummaryService: (any MeetingSummaryServicing)? = nil,
        meetingSummarySettingsStore: (any MeetingSummarySettingsStoring)? = nil,
        transcriptionProgressCenter: TranscriptionProgressCenter? = nil,
        recordingPermissions: (any RecordingPermissions)? = nil,
        meetingTranscriptStore: (any MeetingTranscriptStoring)? = nil,
        knownSpeakerEnrollmentService: (any KnownSpeakerEnrolling)? = nil,
        calendarIntegration: (any CalendarIntegration)? = nil,
        speakerSuggestionService: (any SpeakerSuggestionRecomputing)? = nil,
        screenObservationCapturer: (any MeetingScreenObservationCapturing)? = nil,
        dateProvider: @escaping () -> Date = Date.init,
        meetingIDProvider: @escaping () -> UUID = UUID.init,
        meetingTitleFormatter: DateFormatter = AppViewModel.makeMeetingTitleFormatter()
    ) {
        self.transcriptionProgressCenter = transcriptionProgressCenter ?? TranscriptionProgressCenter()
        self.meetingStore = meetingStore
        self.meetingFileStore = meetingFileStore
        self.recordingService = recordingService
        self.transcriptionService = transcriptionService ?? NoopTranscriptionService()
        self.meetingSummaryService = meetingSummaryService ?? NoopMeetingSummaryService()
        self.meetingSummarySettingsStore = meetingSummarySettingsStore ?? MeetingSummarySettingsStore()
        self.recordingPermissions = recordingPermissions ?? NativeRecordingPermissions()
        self.meetingTranscriptStore = meetingTranscriptStore ?? MeetingTranscriptStore()
        self.knownSpeakerEnrollmentService = knownSpeakerEnrollmentService
        self.calendarIntegration = calendarIntegration ?? NoopCalendarIntegration()
        self.speakerSuggestionService = speakerSuggestionService
        self.screenObservationCapturer = screenObservationCapturer
        self.dateProvider = dateProvider
        self.meetingIDProvider = meetingIDProvider
        self.meetingTitleFormatter = meetingTitleFormatter

        self.transcriptionProgressCenter.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func startRecording() async {
        guard canStartRecording else {
            return
        }

        recoverableRecordingMeetingID = nil
        recordingState = .starting

        switch await recordingPermissions.ensurePermissions() {
        case .granted:
            break
        case .denied(let message):
            recordingState = .failed(message: message)
            return
        }

        var createdArtifacts: MeetingArtifacts?
        var createdMeeting: Meeting?

        do {
            let startedAt = dateProvider()
            let meetingID = meetingIDProvider()
            let matchingEvent = calendarIntegration.eventMatchingRecordingStart(at: startedAt)
            let artifacts = try meetingFileStore.createArtifacts(
                for: meetingID,
                startedAt: startedAt
            )
            createdArtifacts = artifacts

            let meeting = try meetingStore.createMeeting(
                id: meetingID,
                title: resolvedMeetingTitle(for: startedAt, matchingEvent: matchingEvent),
                startedAt: startedAt,
                attendeeNames: matchingEvent?.attendees.map(\.displayName) ?? [],
                calendarEventID: matchingEvent?.id,
                folderURL: artifacts.meetingFolderURL,
                audioFileURL: artifacts.audioFileURL
            )
            createdMeeting = meeting

            try await recordingService.startRecording(
                meeting: meeting,
                outputURL: artifacts.audioFileURL
            )
            await screenObservationCapturer?.start(
                meetingID: meetingID,
                meetingFolderURL: artifacts.meetingFolderURL,
                startedAt: startedAt
            )

            recordingState = .recording(meetingID: meetingID)
            recordingStartedAt = dateProvider()
            activeRecordingTitle = meeting.title
        } catch {
            let startupFailureMessage = error.localizedDescription
            do {
                try await recordingService.stopRecording()
            } catch {
                // Best-effort teardown so a failed start cannot leave partial recorder state behind.
            }
            await screenObservationCapturer?.stop()
            let rollbackFailureMessage = rollbackFailedRecordingStart(
                meeting: createdMeeting,
                artifacts: createdArtifacts
            )
            recordingState = .failed(
                message: rollbackFailureMessage.map {
                    "\(startupFailureMessage) Cleanup failed: \($0)"
                } ?? startupFailureMessage
            )
        }
    }

    func stopRecording() async {
        guard let meetingID = activeOrRecoverableMeetingID else {
            return
        }

        recordingState = .stopping(meetingID: meetingID)

        do {
            try await recordingService.stopRecording()
            await screenObservationCapturer?.stop()
            try meetingStore.finishRecording(
                meetingID: meetingID,
                endedAt: dateProvider()
            )
            recoverableRecordingMeetingID = nil
            recordingState = .idle
            recordingStartedAt = nil
            activeRecordingTitle = nil
            autoRecordingCoordinator?.recordingDidStop()
        } catch {
            recoverableRecordingMeetingID = meetingID
            recordingState = .failed(message: error.localizedDescription)
        }
    }

    func attachAutoRecordingCoordinator(_ coordinator: AutoRecordingCoordinator) {
        autoRecordingCoordinator = coordinator
    }

    func updateAutoRecordingPresence(_ presence: MeetingAppPresence) async {
        switch presence {
        case .candidateActive, .activeMeeting:
            let wasAlreadyPending = isAutoRecordingStartPending
            isAutoRecordingStartPending = !canStopRecording
            if isAutoRecordingStartPending && !wasAlreadyPending {
                autoRecordingDetectedAt = Date()
            }
            autoRecordingStatusText = "Detected meeting activity, waiting 10s"
        case .ending:
            isAutoRecordingStartPending = false
            autoRecordingDetectedAt = nil
            autoRecordingStatusText = "Meeting activity lost, stopping soon"
        case .inactive:
            isAutoRecordingStartPending = false
            autoRecordingDetectedAt = nil
            autoRecordingStatusText = nil
        }

        await autoRecordingCoordinator?.handle(presence)
    }

    var menuBarIconState: MenuBarIconState {
        switch recordingState {
        case .recording, .stopping:
            return .recording
        case .idle, .starting, .failed:
            return isAutoRecordingStartPending ? .pendingAutoRecord : .idle
        }
    }

    var canStartRecording: Bool {
        guard recoverableRecordingMeetingID == nil else {
            return false
        }

        switch recordingState {
        case .idle, .failed:
            return true
        case .starting, .recording, .stopping:
            return false
        }
    }   

    var canStopRecording: Bool {
        activeOrRecoverableMeetingID != nil
    }

    var activeOrRecoverableMeetingID: UUID? {
        switch recordingState {
        case .recording(let meetingID), .stopping(let meetingID):
            return meetingID
        case .idle, .starting:
            return nil
        case .failed:
            return recoverableRecordingMeetingID
        }
    }

    func canDeleteMeeting(_ meeting: Meeting) -> Bool {
        activeOrRecoverableMeetingID != meeting.id
    }

    func deleteMeeting(_ meeting: Meeting) {
        guard canDeleteMeeting(meeting) else {
            return
        }

        do {
            try meetingFileStore.deleteArtifacts(for: meeting)
            try meetingStore.deleteMeeting(meeting)
            deletionErrorMessage = nil
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }

    func clearDeletionError() {
        deletionErrorMessage = nil
    }

    func canTranscribeMeeting(_ meeting: Meeting) -> Bool {
        guard let status = try? meeting.status else {
            return false
        }

        guard !transcriptionProgressCenter.isAnyTranscriptionActive else {
            return false
        }

        switch status {
        case .recorded, .failed, .completed:
            return true
        case .recording, .transcribing:
            return false
        }
    }

    func transcribeMeeting(_ meeting: Meeting) async {
        transcriptionErrorMessage = nil

        do {
            try await transcriptionService.transcribe(meetingID: meeting.id)
        } catch {
            transcriptionErrorMessage = error.localizedDescription
        }
    }

    func clearTranscriptionError() {
        transcriptionErrorMessage = nil
    }

    func generateSummary(for meeting: Meeting) async {
        summaryError = nil

        guard meetingSummarySettingsStore.validatedSettings() != nil else {
            summaryError = SummaryErrorState(
                meetingID: meeting.id,
                message: MeetingSummaryServiceError.settingsIncomplete.localizedDescription
            )
            return
        }

        if meeting.summaryText != nil {
            pendingSummaryReplacementMeetingID = meeting.id
            summaryConfirmationMeetingID = meeting.id
            return
        }

        await runSummaryGeneration(for: meeting.id)
    }

    func confirmSummaryReplacement() async {
        guard let meetingID = pendingSummaryReplacementMeetingID else {
            return
        }

        pendingSummaryReplacementMeetingID = nil
        summaryConfirmationMeetingID = nil
        await runSummaryGeneration(for: meetingID)
    }

    func cancelSummaryReplacement() {
        pendingSummaryReplacementMeetingID = nil
        summaryConfirmationMeetingID = nil
    }

    func summaryErrorMessage(forMeeting meetingID: UUID) -> String? {
        guard summaryError?.meetingID == meetingID else {
            return nil
        }

        return summaryError?.message
    }

    func renameMeeting(_ meeting: Meeting, title: String) async throws {
        do {
            try meetingStore.renameMeeting(
                meetingID: meeting.id,
                title: title,
                updatedAt: dateProvider()
            )
            renameMeetingErrorMessage = nil
        } catch {
            renameMeetingErrorMessage = error.localizedDescription
            throw error
        }
    }

    func clearRenameMeetingError() {
        renameMeetingErrorMessage = nil
    }

    func calendarEvents(for meeting: Meeting) -> [UpcomingCalendarEvent] {
        calendarEventCandidatesByMeetingID[meeting.id] ?? []
    }

    func reloadCalendarEvents(for meeting: Meeting) {
        calendarEventCandidatesByMeetingID[meeting.id] = calendarIntegration.calendarEventsForRecording(
            startedAt: meeting.startedAt,
            endedAt: meeting.endedAt
        )
    }

    func selectCalendarEvent(_ event: UpcomingCalendarEvent, for meeting: Meeting) {
        do {
            try meetingStore.updateCalendarEvent(
                meetingID: meeting.id,
                eventTitle: event.title,
                attendeeNames: event.attendees.map(\.displayName),
                calendarEventID: event.id,
                updatedAt: dateProvider()
            )
            calendarEventSelectionErrorMessage = nil
            Task {
                await speakerSuggestionService?.recomputeSuggestions(for: meeting.id)
            }
        } catch {
            calendarEventSelectionErrorMessage = error.localizedDescription
        }
    }

    func clearCalendarEventSelectionError() {
        calendarEventSelectionErrorMessage = nil
    }

    func pendingSpeakerSuggestions(for meetingID: UUID) -> [SpeakerIdentitySuggestion] {
        speakerSuggestionService?.pendingSuggestions(for: meetingID) ?? []
    }

    func acceptSpeakerSuggestion(_ suggestion: SpeakerIdentitySuggestion) {
        speakerSuggestionService?.acceptSuggestion(id: suggestion.id)
    }

    func dismissSpeakerSuggestion(_ suggestion: SpeakerIdentitySuggestion) {
        speakerSuggestionService?.dismissSuggestion(id: suggestion.id)
    }

    func storeWaveform(meetingID: UUID, samples: [Double]) {
        try? meetingStore.storeWaveform(meetingID: meetingID, samples: samples)
    }

    func renameSpeaker(
        meetingID: UUID,
        speakerID: String,
        displayName: String
    ) async throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let transcript = try meetingTranscriptStore.renameSpeaker(
                id: speakerID,
                to: trimmedName,
                in: meetingID
            )
            renameSpeakerErrorMessage = nil

            if let speaker = transcript.speakers.first(where: { $0.id == speakerID }) {
                do {
                    try await knownSpeakerEnrollmentService?.enroll(
                        displayName: trimmedName,
                        speaker: speaker,
                        meetingID: meetingID
                    )
                } catch {
                    // Best-effort enrollment. Keep the successful rename.
                }
            }
        } catch {
            renameSpeakerErrorMessage = error.localizedDescription
            throw error
        }
    }

    func updateTranscriptSegmentText(
        meetingID: UUID,
        segmentID: UUID,
        text: String
    ) async throws {
        do {
            _ = try meetingTranscriptStore.updateSegmentText(
                segmentID: segmentID,
                text: text,
                in: meetingID
            )
            renameSpeakerErrorMessage = nil
        } catch {
            renameSpeakerErrorMessage = error.localizedDescription
            throw error
        }
    }

    func splitTranscriptSegment(
        meetingID: UUID,
        segmentID: UUID,
        cursorOffset: Int
    ) async throws -> TranscriptSegment {
        do {
            let segment = try meetingTranscriptStore.splitSegment(
                segmentID: segmentID,
                at: cursorOffset,
                in: meetingID
            )
            renameSpeakerErrorMessage = nil
            return segment
        } catch {
            renameSpeakerErrorMessage = error.localizedDescription
            throw error
        }
    }

    func mergeTranscriptSegmentWithPrevious(
        meetingID: UUID,
        segmentID: UUID
    ) async throws -> TranscriptSegment {
        do {
            let segment = try meetingTranscriptStore.mergeSegmentWithPrevious(
                segmentID: segmentID,
                in: meetingID
            )
            renameSpeakerErrorMessage = nil
            return segment
        } catch {
            renameSpeakerErrorMessage = error.localizedDescription
            throw error
        }
    }

    func assignTranscriptSegment(
        meetingID: UUID,
        segmentID: UUID,
        speakerName: String
    ) async throws {
        let trimmedName = speakerName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try meetingTranscriptStore.assignSegment(
                segmentID: segmentID,
                toSpeakerNamed: trimmedName,
                in: meetingID
            )
            renameSpeakerErrorMessage = nil
        } catch {
            renameSpeakerErrorMessage = error.localizedDescription
            throw error
        }
    }

    func clearRenameSpeakerError() {
        renameSpeakerErrorMessage = nil
    }

    func loadUpcomingCalendarEvent() async {
        upcomingCalendarEvent = calendarIntegration.upcomingEventForToday()
    }

    func transcriptionProgress(for meetingID: UUID) -> Double? {
        transcriptionProgressCenter.progress(for: meetingID)
    }

    func diarizationProgress(for meetingID: UUID) -> DiarizationProgressState? {
        transcriptionProgressCenter.diarizationProgress(for: meetingID)
    }

    private func resolvedMeetingTitle(
        for startedAt: Date,
        matchingEvent: UpcomingCalendarEvent?
    ) -> String {
        if let matchingEvent {
            return matchingEvent.title
        }

        return meetingTitleFormatter.string(from: startedAt)
    }

    nonisolated private static func makeMeetingTitleFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }

    private func rollbackFailedRecordingStart(
        meeting: Meeting?,
        artifacts: MeetingArtifacts?
    ) -> String? {
        var cleanupFailureMessage: String?

        if let meeting {
            do {
                try meetingStore.deleteMeeting(meeting)
            } catch {
                cleanupFailureMessage = error.localizedDescription
            }
        }

        if let artifacts {
            do {
                try removeArtifactsDirectory(at: artifacts.meetingFolderURL)
            } catch {
                cleanupFailureMessage = cleanupFailureMessage ?? error.localizedDescription
            }
        }

        return cleanupFailureMessage
    }

    private func removeArtifactsDirectory(at meetingFolderURL: URL) throws {
        let fileManager = meetingFileStore.fileManager
        guard fileManager.fileExists(atPath: meetingFolderURL.path()) else {
            return
        }

        try fileManager.removeItem(at: meetingFolderURL)
    }

    private func runSummaryGeneration(for meetingID: UUID) async {
        summarizingMeetingID = meetingID
        defer { summarizingMeetingID = nil }

        do {
            let summary = try await meetingSummaryService.summarize(meetingID: meetingID)
            try meetingStore.saveSummary(
                meetingID: meetingID,
                summary: summary,
                updatedAt: dateProvider()
            )
        } catch {
            summaryError = SummaryErrorState(meetingID: meetingID, message: error.localizedDescription)
        }
    }
}

private struct SummaryErrorState {
    let meetingID: UUID
    let message: String
}

extension AppViewModel: AutoRecordingIntentSink {
    func requestAutoRecordingStart() async {
        guard canStartRecording else {
            isAutoRecordingStartPending = false
            return
        }

        isAutoRecordingStartPending = false
        autoRecordingStatusText = "Recording started automatically"
        await startRecording()

        if case .recording = recordingState {
            autoRecordingCoordinator?.recordingDidStart()
        }
    }

    func requestAutoRecordingStop() async {
        isAutoRecordingStartPending = false

        guard canStopRecording else {
            return
        }

        await stopRecording()

        if case .idle = recordingState {
            autoRecordingStatusText = nil
        }
    }
}

extension AppViewModel: AutoRecordingPresenceUpdating {}

private struct NoopMeetingSummaryService: MeetingSummaryServicing {
    func summarize(meetingID _: UUID) async throws -> String {
        throw MeetingSummaryServiceError.settingsIncomplete
    }
}
