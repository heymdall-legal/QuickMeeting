import Foundation
import Testing
@testable import QuickMeeting

struct MeetingFileStoreTests {
    @Test
    func createArtifactsCreatesMeetingFolderAndAudioFilePath() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MeetingFileStore(fileManager: fileManager, rootURL: rootURL)

        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)

        let artifacts = try store.createArtifacts(for: meetingID, startedAt: startedAt)

        var isDirectory = ObjCBool(false)
        let folderExists = fileManager.fileExists(
            atPath: artifacts.meetingFolderURL.path,
            isDirectory: &isDirectory
        )

        #expect(folderExists)
        #expect(isDirectory.boolValue)
        #expect(artifacts.meetingFolderURL.lastPathComponent == meetingID.uuidString)
        #expect(
            artifacts.audioFileURL.deletingLastPathComponent().standardizedFileURL
                == artifacts.meetingFolderURL.standardizedFileURL
        )
        #expect(artifacts.systemAudioFileURL.lastPathComponent == "system_audio.m4a")
        #expect(artifacts.microphoneAudioFileURL.lastPathComponent == "microphone.m4a")
        #expect(artifacts.mixedPreviewAudioFileURL.lastPathComponent == "mixed_preview.m4a")
        #expect(artifacts.audioFileURL == artifacts.mixedPreviewAudioFileURL)
    }

    @Test
    func deleteArtifactsRemovesMeetingFolderAndAudioFile() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MeetingFileStore(fileManager: fileManager, rootURL: rootURL)
        let meetingID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let artifacts = try store.createArtifacts(for: meetingID, startedAt: startedAt)
        fileManager.createFile(atPath: artifacts.audioFileURL.path, contents: Data("stub".utf8))
        let meeting = Meeting(
            id: meetingID,
            title: "Delete Me",
            startedAt: startedAt,
            status: .recorded,
            audioFilePath: artifacts.audioFileURL.path
        )

        try store.deleteArtifacts(for: meeting)

        #expect(!fileManager.fileExists(atPath: artifacts.audioFileURL.path))
        #expect(!fileManager.fileExists(atPath: artifacts.meetingFolderURL.path))
    }

    @Test
    func createsScreenObservationDirectoryInsideMeetingFolder() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MeetingFileStore(fileManager: .default, rootURL: rootURL)
        let meetingID = UUID()
        let artifacts = try store.createArtifacts(for: meetingID, startedAt: Date())

        let directory = try store.screenObservationsDirectory(forMeetingFolder: artifacts.meetingFolderURL)

        #expect(directory.lastPathComponent == "screen-observations")
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(directory.path.hasPrefix(artifacts.meetingFolderURL.path))
    }

    @Test
    func relativePathForScreenObservationStaysInsideMeetingFolder() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MeetingFileStore(fileManager: .default, rootURL: rootURL)
        let artifacts = try store.createArtifacts(for: UUID(), startedAt: Date())
        let imageURL = artifacts.meetingFolderURL
            .appendingPathComponent("screen-observations", isDirectory: true)
            .appendingPathComponent("0001.jpg")

        let relativePath = try store.relativePath(for: imageURL, inMeetingFolder: artifacts.meetingFolderURL)

        #expect(relativePath == "screen-observations/0001.jpg")
    }

    @Test
    func relativePathRejectsFileOutsideMeetingFolder() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MeetingFileStore(fileManager: .default, rootURL: rootURL)
        let artifacts = try store.createArtifacts(for: UUID(), startedAt: Date())
        let outsideURL = rootURL
            .appendingPathComponent("outside", isDirectory: true)
            .appendingPathComponent("0001.jpg")

        #expect(throws: MeetingStoreError.audioFileOutsideRecordingFolder) {
            try store.relativePath(for: outsideURL, inMeetingFolder: artifacts.meetingFolderURL)
        }
    }
}
