import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct ScreenObservationStoreTests {
    @Test
    func savesAndLoadsObservationsForMeeting() throws {
        let harness = try ScreenObservationStoreHarness()
        let meetingID = UUID()
        let observation = ScreenObservation(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            meetingID: meetingID,
            capturedAtOffset: 12,
            imageRelativePath: "screen-observations/0001.jpg",
            thumbnailRelativePath: "screen-observations/0001-thumb.jpg",
            sourceAppBundleID: "com.apple.Safari",
            sourceWindowTitle: "Kontur Talk",
            textBoxes: [
                ScreenTextObservation(text: "Masha", boundingBox: UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1))
            ],
            activeTile: ScreenTileObservation(
                boundingBox: UnitRect(x: 0, y: 0, width: 0.5, height: 0.5),
                matchedName: "Masha",
                highlightScore: 0.91
            )
        )

        try harness.store.saveObservation(observation)

        #expect(try harness.store.observations(for: meetingID) == [observation])
    }

    @Test
    func replacesPendingSuggestionsOnRecomputeButKeepsAccepted() throws {
        let harness = try ScreenObservationStoreHarness()
        let meetingID = UUID()
        let accepted = SpeakerIdentitySuggestion(
            id: UUID(),
            meetingID: meetingID,
            speakerID: "speaker-1",
            proposedName: "Masha",
            confidence: .high,
            reason: "Seen in active tile",
            evidenceImageRelativePath: "screen-observations/0001.jpg",
            evidenceThumbnailRelativePath: nil,
            observationID: UUID(),
            capturedAtOffset: 2,
            status: .accepted
        )
        let pending = SpeakerIdentitySuggestion(
            id: UUID(),
            meetingID: meetingID,
            speakerID: "speaker-2",
            proposedName: "Ilya",
            confidence: .medium,
            reason: "Seen in active tile",
            evidenceImageRelativePath: "screen-observations/0002.jpg",
            evidenceThumbnailRelativePath: nil,
            observationID: UUID(),
            capturedAtOffset: 8
        )
        let replacement = SpeakerIdentitySuggestion(
            id: UUID(),
            meetingID: meetingID,
            speakerID: "speaker-2",
            proposedName: "Olga",
            confidence: .high,
            reason: "Seen in active tile",
            evidenceImageRelativePath: "screen-observations/0003.jpg",
            evidenceThumbnailRelativePath: nil,
            observationID: UUID(),
            capturedAtOffset: 9
        )

        try harness.store.saveSuggestions([accepted, pending])
        try harness.store.replacePendingSuggestions(for: meetingID, with: [replacement])

        let suggestions = try harness.store.suggestions(for: meetingID)
        #expect(suggestions.map(\.proposedName).sorted() == ["Masha", "Olga"])
        #expect(suggestions.first(where: { $0.proposedName == "Masha" })?.status == .accepted)
        #expect(suggestions.first(where: { $0.proposedName == "Olga" })?.status == .pending)
    }

    @Test
    func dismissedKeysAreReturnedForMeeting() throws {
        let harness = try ScreenObservationStoreHarness()
        let meetingID = UUID()
        let suggestion = SpeakerIdentitySuggestion(
            id: UUID(),
            meetingID: meetingID,
            speakerID: "speaker-1",
            proposedName: "Masha",
            confidence: .high,
            reason: "Seen in active tile",
            evidenceImageRelativePath: "screen-observations/0001.jpg",
            evidenceThumbnailRelativePath: nil,
            observationID: UUID(),
            capturedAtOffset: 2,
            status: .dismissed
        )

        try harness.store.saveSuggestions([suggestion])

        #expect(try harness.store.dismissedKeys(for: meetingID) == [
            SpeakerIdentitySuggestionKey(speakerID: "speaker-1", proposedName: "Masha")
        ])
    }
}

@MainActor
private struct ScreenObservationStoreHarness {
    let container: ModelContainer
    let store: ScreenObservationStore

    init() throws {
        let schema = Schema([
            PersistedScreenObservation.self,
            PersistedSpeakerIdentitySuggestion.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        store = ScreenObservationStore(modelContext: ModelContext(container))
    }
}
