//
//  MeetingFileStore.swift
//  QuickMeeting
//
//  Created by heymdall on 04.05.2026.
//

import Foundation

struct MeetingArtifacts {
    let meetingFolderURL: URL
    let audioFileURL: URL
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
            audioFileURL: meetingFolderURL.appendingPathComponent("audio.wav")
        )
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
