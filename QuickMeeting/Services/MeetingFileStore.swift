//
//  MeetingFileStore.swift
//  QuickMeeting
//
//  Created by heymdall on 04.05.2026.
//

import Foundation

struct MeetingArtifacts {
    static let systemAudioFilename = "system_audio.m4a"
    static let microphoneAudioFilename = "microphone.m4a"
    static let mixedPreviewAudioFilename = "mixed_preview.m4a"

    let meetingFolderURL: URL
    let systemAudioFileURL: URL
    let microphoneAudioFileURL: URL
    let mixedPreviewAudioFileURL: URL

    /// The headroom-safe mixed track remains the primary meeting audio for
    /// playback and for transcription fallback when isolated tracks are absent.
    var audioFileURL: URL {
        mixedPreviewAudioFileURL
    }
}

struct MeetingFileStore {
    let fileManager: FileManager
    let rootURL: URL

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? Self.defaultRootURL(fileManager: fileManager)
    }

    func createArtifacts(for meetingID: UUID, startedAt _: Date) throws -> MeetingArtifacts {
        let meetingFolderURL = rootURL
            .standardizedFileURL
            .appendingPathComponent(meetingID.uuidString, isDirectory: true)

        try fileManager.createDirectory(
            at: meetingFolderURL,
            withIntermediateDirectories: true
        )

        return MeetingArtifacts(
            meetingFolderURL: meetingFolderURL,
            systemAudioFileURL: meetingFolderURL.appendingPathComponent(MeetingArtifacts.systemAudioFilename),
            microphoneAudioFileURL: meetingFolderURL.appendingPathComponent(MeetingArtifacts.microphoneAudioFilename),
            mixedPreviewAudioFileURL: meetingFolderURL.appendingPathComponent(MeetingArtifacts.mixedPreviewAudioFilename)
        )
    }

    func screenObservationsDirectory(forMeetingFolder meetingFolderURL: URL) throws -> URL {
        let directory = meetingFolderURL
            .standardizedFileURL
            .appendingPathComponent("screen-observations", isDirectory: true)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory
    }

    func relativePath(for fileURL: URL, inMeetingFolder meetingFolderURL: URL) throws -> String {
        let normalizedFileURL = fileURL.standardizedFileURL
        let normalizedMeetingFolderURL = meetingFolderURL.standardizedFileURL

        guard Self.isFileURL(normalizedFileURL, inside: normalizedMeetingFolderURL) else {
            throw MeetingStoreError.audioFileOutsideRecordingFolder
        }

        let folderComponents = normalizedMeetingFolderURL.pathComponents
        let fileComponents = normalizedFileURL.pathComponents
        return fileComponents.dropFirst(folderComponents.count).joined(separator: "/")
    }

    func deleteArtifacts(for meeting: Meeting) throws {
        let audioFileURL = URL(fileURLWithPath: meeting.audioFilePath).standardizedFileURL
        let meetingFolderURL = audioFileURL.deletingLastPathComponent().standardizedFileURL
        let normalizedRootURL = rootURL.standardizedFileURL

        guard Self.isFileURL(meetingFolderURL, inside: normalizedRootURL) else {
            return
        }

        if fileManager.fileExists(atPath: meetingFolderURL.path) {
            try fileManager.removeItem(at: meetingFolderURL)
            return
        }

        if fileManager.fileExists(atPath: audioFileURL.path) {
            try fileManager.removeItem(at: audioFileURL)
        }
    }

    private static func isFileURL(_ fileURL: URL, inside directoryURL: URL) -> Bool {
        let directoryComponents = directoryURL.pathComponents
        let fileComponents = fileURL.pathComponents

        guard fileComponents.count > directoryComponents.count else {
            return false
        }

        return Array(fileComponents.prefix(directoryComponents.count)) == directoryComponents
    }

    private static func defaultRootURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return applicationSupportURL
            .appendingPathComponent("QuickMeeting", isDirectory: true)
            .appendingPathComponent("Meetings", isDirectory: true)
    }
}
