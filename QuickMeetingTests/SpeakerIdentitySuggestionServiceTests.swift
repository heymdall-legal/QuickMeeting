import Foundation
import Testing
@testable import QuickMeeting

struct SpeakerIdentitySuggestionServiceTests {
    @Test
    func activeTileEvidenceOverlappingSegmentCreatesHighConfidenceSuggestion() {
        let service = SpeakerIdentitySuggestionService()
        let meetingID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let observationID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let speakerID = "speaker-1"
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: speakerID, displayName: "Speaker 1")],
            segments: [
                TranscriptSegment(
                    text: "Hello",
                    startTime: 12,
                    endTime: 18,
                    speakerID: speakerID
                )
            ]
        )
        let observations = [
            ScreenObservation(
                id: observationID,
                meetingID: meetingID,
                capturedAtOffset: 14,
                imageRelativePath: "screen-observations/0001.jpg",
                thumbnailRelativePath: "screen-observations/0001-thumb.jpg",
                sourceAppBundleID: "com.apple.Safari",
                sourceWindowTitle: "Kontur Talk",
                textBoxes: [
                    ScreenTextObservation(
                        text: "Masha",
                        boundingBox: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)
                    )
                ],
                activeTile: ScreenTileObservation(
                    boundingBox: UnitRect(x: 0.05, y: 0.05, width: 0.4, height: 0.4),
                    matchedName: "Masha",
                    highlightScore: 0.92
                )
            )
        ]

        let suggestions = service.suggestions(
            meetingID: meetingID,
            attendeeNames: ["Masha", "Ilya"],
            transcript: transcript,
            observations: observations,
            dismissed: []
        )

        #expect(suggestions.count == 1)
        #expect(suggestions.first?.meetingID == meetingID)
        #expect(suggestions.first?.speakerID == speakerID)
        #expect(suggestions.first?.proposedName == "Masha")
        #expect(suggestions.first?.confidence == .high)
        #expect(suggestions.first?.reason == "Seen in active tile")
        #expect(suggestions.first?.evidenceImageRelativePath == "screen-observations/0001.jpg")
    }

    @Test
    func evidenceMustMatchCurrentAttendeeList() {
        let service = SpeakerIdentitySuggestionService()
        let meetingID = UUID()
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", startTime: 1, endTime: 4, speakerID: "speaker-1")]
        )
        let observations = [
            ScreenObservation(
                meetingID: meetingID,
                capturedAtOffset: 2,
                imageRelativePath: "screen-observations/0001.jpg",
                thumbnailRelativePath: nil,
                activeTile: ScreenTileObservation(
                    boundingBox: UnitRect(x: 0, y: 0, width: 1, height: 1),
                    matchedName: "Not In Calendar",
                    highlightScore: 0.9
                )
            )
        ]

        let suggestions = service.suggestions(
            meetingID: meetingID,
            attendeeNames: ["Masha"],
            transcript: transcript,
            observations: observations,
            dismissed: []
        )

        #expect(suggestions.isEmpty)
    }

    @Test
    func nonOverlappingEvidenceDoesNotAssignSpeaker() {
        let service = SpeakerIdentitySuggestionService()
        let meetingID = UUID()
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", startTime: 20, endTime: 24, speakerID: "speaker-1")]
        )
        let observations = [
            ScreenObservation(
                meetingID: meetingID,
                capturedAtOffset: 5,
                imageRelativePath: "screen-observations/0001.jpg",
                thumbnailRelativePath: nil,
                activeTile: ScreenTileObservation(
                    boundingBox: UnitRect(x: 0, y: 0, width: 1, height: 1),
                    matchedName: "Masha",
                    highlightScore: 0.9
                )
            )
        ]

        let suggestions = service.suggestions(
            meetingID: meetingID,
            attendeeNames: ["Masha"],
            transcript: transcript,
            observations: observations,
            dismissed: []
        )

        #expect(suggestions.isEmpty)
    }

    @Test
    func dismissedSuggestionIsNotReturnedAgain() {
        let service = SpeakerIdentitySuggestionService()
        let meetingID = UUID()
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", startTime: 1, endTime: 4, speakerID: "speaker-1")]
        )
        let observations = [
            ScreenObservation(
                meetingID: meetingID,
                capturedAtOffset: 2,
                imageRelativePath: "screen-observations/0001.jpg",
                thumbnailRelativePath: nil,
                activeTile: ScreenTileObservation(
                    boundingBox: UnitRect(x: 0, y: 0, width: 1, height: 1),
                    matchedName: "Masha",
                    highlightScore: 0.9
                )
            )
        ]
        let dismissed = Set([
            SpeakerIdentitySuggestionKey(speakerID: "speaker-1", proposedName: "Masha")
        ])

        let suggestions = service.suggestions(
            meetingID: meetingID,
            attendeeNames: ["Masha"],
            transcript: transcript,
            observations: observations,
            dismissed: dismissed
        )

        #expect(suggestions.isEmpty)
    }
}
