//
//  TranscriptionService.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Foundation

enum TranscriptionServiceError: LocalizedError, Equatable {
    case meetingNotTranscribable
    case audioFileMissing
    case noInstalledDefaultModel
    case transcriptionAlreadyActive

    var errorDescription: String? {
        switch self {
        case .meetingNotTranscribable:
            return "This meeting can't be transcribed right now."
        case .audioFileMissing:
            return "Recording file is missing."
        case .noInstalledDefaultModel:
            return "No installed default transcription model is available."
        case .transcriptionAlreadyActive:
            return "Another transcription is already in progress."
        }
    }
}

protocol TranscriptionServicing: AnyObject {
    func transcribe(meetingID: UUID) async throws
}

@MainActor
final class TranscriptionService: TranscriptionServicing {
    private let meetingStore: MeetingStore
    private let modelStore: any WhisperModelStore
    private let modelSettingsStore: ModelSettingsStore
    private let backend: any WhisperTranscriptionBackend
    private let progressCenter: TranscriptionProgressCenter
    private let artifactWriter: TranscriptionArtifactWriter
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private var activeMeetingID: UUID?

    init(
        meetingStore: MeetingStore,
        modelStore: any WhisperModelStore,
        modelSettingsStore: ModelSettingsStore,
        backend: any WhisperTranscriptionBackend,
        progressCenter: TranscriptionProgressCenter,
        artifactWriter: TranscriptionArtifactWriter? = nil,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.meetingStore = meetingStore
        self.modelStore = modelStore
        self.modelSettingsStore = modelSettingsStore
        self.backend = backend
        self.progressCenter = progressCenter
        self.artifactWriter = artifactWriter ?? TranscriptionArtifactWriter(fileManager: fileManager)
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    func transcribe(meetingID: UUID) async throws {
        guard activeMeetingID == nil else {
            throw TranscriptionServiceError.transcriptionAlreadyActive
        }

        let meeting = try meetingStore.fetchMeeting(id: meetingID)
        let status = try meeting.status
        guard status == .recorded || status == .failed else {
            throw TranscriptionServiceError.meetingNotTranscribable
        }

        let audioFileURL = URL(fileURLWithPath: meeting.audioFilePath)
        guard fileManager.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionServiceError.audioFileMissing
        }

        let installedModels = try await modelStore.installedModels()
        guard
            let defaultModelID = modelSettingsStore.defaultModelID,
            installedModels[defaultModelID] != nil,
            let model = TranscriptionModelCatalog.model(for: defaultModelID),
            let modelFolderURL = try await modelStore.installedModelURL(for: model)
        else {
            throw TranscriptionServiceError.noInstalledDefaultModel
        }

        activeMeetingID = meetingID
        try meetingStore.startTranscription(meetingID: meetingID, updatedAt: dateProvider())
        progressCenter.startTracking(meetingID: meetingID)

        defer {
            progressCenter.finishTracking(meetingID: meetingID)
            activeMeetingID = nil
        }

        do {
            let result = try await backend.transcribe(
                TranscriptionRequest(
                    audioFileURL: audioFileURL,
                    model: model,
                    modelFolderURL: modelFolderURL,
                    onProgress: { [progressCenter] progress in
                        Task { @MainActor in
                            progressCenter.updateProgress(progress, for: meetingID)
                        }
                    }
                )
            )
            let artifacts = try artifactWriter.writeArtifacts(
                for: result,
                in: audioFileURL.deletingLastPathComponent()
            )
            try meetingStore.completeTranscription(
                meetingID: meetingID,
                transcriptFileURL: artifacts.transcriptFileURL,
                transcriptPreview: artifacts.previewText,
                updatedAt: dateProvider()
            )
        } catch {
            try? meetingStore.failTranscription(meetingID: meetingID, updatedAt: dateProvider())
            throw error
        }
    }
}

final class NoopTranscriptionService: TranscriptionServicing {
    func transcribe(meetingID _: UUID) async throws {}
}
