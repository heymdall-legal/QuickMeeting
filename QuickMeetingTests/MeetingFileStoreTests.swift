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
        #expect(artifacts.audioFileURL.lastPathComponent == "audio.wav")
    }
}
