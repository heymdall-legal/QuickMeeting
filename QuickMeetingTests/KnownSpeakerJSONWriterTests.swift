import Foundation
import Testing
@testable import QuickMeeting

struct KnownSpeakerJSONWriterTests {
    @Test
    func writeKnownSpeakersFileUsesSidecarShape() throws {
        let writer = KnownSpeakerJSONWriter(fileManager: .default)
        let outputURL = try writer.write(
            speakers: [
                KnownSpeakerExport(id: "known-1", centroids: [[0.1, 0.2], [0.3, 0.4]])
            ],
            directoryURL: FileManager.default.temporaryDirectory
        )

        let data = try Data(contentsOf: outputURL)
        let payload = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let first = try #require(payload?.first)
        #expect(first["id"] as? String == "known-1")
        #expect((first["centroids"] as? [[Double]])?.count == 2)
    }
}
