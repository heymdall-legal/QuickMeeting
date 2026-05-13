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
    @Published private(set) var deletionErrorMessage: String?
    @Published private(set) var transcriptionErrorMessage: String?
    @Published private(set) var renameSpeakerErrorMessage: String?
    @Published private(set) var renameMeetingErrorMessage: String?
    @Published private(set) var upcomingCalendarEvent: UpcomingCalendarEvent?

    let transcriptionProgressCenter: TranscriptionProgressCenter
    private let meetingStore: MeetingStore
    private let meetingFileStore: MeetingFileStore
    private let recordingService: any RecordingService
    private let transcriptionService: any TranscriptionServicing
    private let meetingTranscriptStore: any MeetingTranscriptStoring
    private let recordingPermissions: any RecordingPermissions
    private let calendarIntegration: any CalendarIntegration
    private let dateProvider: () -> Date
    private let meetingIDProvider: () -> UUID
    private let meetingTitleFormatter: DateFormatter
    private var recoverableRecordingMeetingID: UUID?
    private var cancellables = Set<AnyCancellable>()

    init(
        meetingStore: MeetingStore,
        meetingFileStore: MeetingFileStore,
        recordingService: any RecordingService,
        transcriptionService: (any TranscriptionServicing)? = nil,
        transcriptionProgressCenter: TranscriptionProgressCenter? = nil,
        recordingPermissions: (any RecordingPermissions)? = nil,
        meetingTranscriptStore: (any MeetingTranscriptStoring)? = nil,
        calendarIntegration: (any CalendarIntegration)? = nil,
        dateProvider: @escaping () -> Date = Date.init,
        meetingIDProvider: @escaping () -> UUID = UUID.init,
        meetingTitleFormatter: DateFormatter = AppViewModel.makeMeetingTitleFormatter()
    ) {
        self.transcriptionProgressCenter = transcriptionProgressCenter ?? TranscriptionProgressCenter()
        self.meetingStore = meetingStore
        self.meetingFileStore = meetingFileStore
        self.recordingService = recordingService
        self.transcriptionService = transcriptionService ?? NoopTranscriptionService()
        self.recordingPermissions = recordingPermissions ?? NativeRecordingPermissions()
        self.meetingTranscriptStore = meetingTranscriptStore ?? MeetingTranscriptStore()
        self.calendarIntegration = calendarIntegration ?? NoopCalendarIntegration()
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
                folderURL: artifacts.meetingFolderURL,
                audioFileURL: artifacts.audioFileURL
            )
            createdMeeting = meeting

            try await recordingService.startRecording(
                meeting: meeting,
                outputURL: artifacts.audioFileURL
            )

            recordingState = .recording(meetingID: meetingID)
        } catch {
            let startupFailureMessage = error.localizedDescription
            do {
                try await recordingService.stopRecording()
            } catch {
                // Best-effort teardown so a failed start cannot leave partial recorder state behind.
            }
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
            try meetingStore.finishRecording(
                meetingID: meetingID,
                endedAt: dateProvider()
            )
            recoverableRecordingMeetingID = nil
            recordingState = .idle
        } catch {
            recoverableRecordingMeetingID = meetingID
            recordingState = .failed(message: error.localizedDescription)
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

    func renameSpeaker(
        meetingID: UUID,
        speakerID: String,
        displayName: String
    ) async throws {
        do {
            _ = try meetingTranscriptStore.renameSpeaker(
                id: speakerID,
                to: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
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

    func diarizationProgress(for meetingID: UUID) -> Double? {
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
}
