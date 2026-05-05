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
