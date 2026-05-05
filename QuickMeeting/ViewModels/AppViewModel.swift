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

    private let meetingStore: MeetingStore
    private let meetingFileStore: MeetingFileStore
    private let recordingService: any RecordingService
    private let recordingPermissions: any RecordingPermissions
    private let dateProvider: () -> Date
    private let meetingIDProvider: () -> UUID
    private let meetingTitleProvider: (Date) -> String
    private var recoverableRecordingMeetingID: UUID?

    init(
        meetingStore: MeetingStore,
        meetingFileStore: MeetingFileStore,
        recordingService: any RecordingService,
        recordingPermissions: (any RecordingPermissions)? = nil,
        dateProvider: @escaping () -> Date = Date.init,
        meetingIDProvider: @escaping () -> UUID = UUID.init,
        meetingTitleProvider: @escaping (Date) -> String = { _ in "Untitled Meeting" }
    ) {
        self.meetingStore = meetingStore
        self.meetingFileStore = meetingFileStore
        self.recordingService = recordingService
        self.recordingPermissions = recordingPermissions ?? NativeRecordingPermissions()
        self.dateProvider = dateProvider
        self.meetingIDProvider = meetingIDProvider
        self.meetingTitleProvider = meetingTitleProvider
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
            let artifacts = try meetingFileStore.createArtifacts(
                for: meetingID,
                startedAt: startedAt
            )
            createdArtifacts = artifacts

            let meeting = try meetingStore.createMeeting(
                id: meetingID,
                title: meetingTitleProvider(startedAt),
                startedAt: startedAt,
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
