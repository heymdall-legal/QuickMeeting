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
            ),
            activeObservation(meetingID: meetingID, offset: 15, name: "Masha", score: 0.90, sequence: 2),
            activeObservation(meetingID: meetingID, offset: 16, name: "Masha", score: 0.88, sequence: 3),
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
        #expect(suggestions.first?.confidencePercent ?? 0 >= 85)
        #expect(suggestions.first?.reason == "Active speaker evidence")
        #expect(suggestions.first?.evidenceSummary.supportingObservationCount == 3)
        #expect(suggestions.first?.evidenceSummary.supportingDuration == 6)
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
        let observations = [1.5, 2.5, 3.0].enumerated().map { index, offset in
            activeObservation(
                meetingID: meetingID,
                offset: offset,
                name: "Masha",
                score: 0.9,
                sequence: index + 1
            )
        }
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

    @Test
    func conflictingNamesForOneOfflineSpeakerDoNotCreateSuggestion() {
        let service = SpeakerIdentitySuggestionService()
        let meetingID = UUID()
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [
                TranscriptSegment(text: "Long turn", startTime: 0, endTime: 20, speakerID: "speaker-1")
            ]
        )
        let observations = [
            activeObservation(meetingID: meetingID, offset: 2, name: "Masha", score: 0.9, sequence: 1),
            activeObservation(meetingID: meetingID, offset: 4, name: "Masha", score: 0.9, sequence: 2),
            activeObservation(meetingID: meetingID, offset: 6, name: "Ilya", score: 0.9, sequence: 3),
            activeObservation(meetingID: meetingID, offset: 8, name: "Ilya", score: 0.9, sequence: 4),
        ]

        let suggestions = service.suggestions(
            meetingID: meetingID,
            attendeeNames: ["Masha", "Ilya"],
            transcript: transcript,
            observations: observations,
            dismissed: []
        )

        #expect(suggestions.isEmpty)
    }

    @Test
    func supportsMoreThanFourOfflineSpeakersWithoutRealtimeClusterMapping() {
        let service = SpeakerIdentitySuggestionService()
        let meetingID = UUID()
        let names = ["Masha", "Ilya", "Olga", "Pavel", "Anna", "Denis"]
        let speakers = names.indices.map {
            TranscriptSpeaker(id: "speaker-\($0 + 1)", displayName: "Speaker \($0 + 1)")
        }
        let segments = names.indices.map { index in
            let start = TimeInterval(index * 10)
            return TranscriptSegment(
                text: "Turn \(index + 1)",
                startTime: start,
                endTime: start + 8,
                speakerID: speakers[index].id
            )
        }
        let observations = names.indices.flatMap { index -> [ScreenObservation] in
            let start = TimeInterval(index * 10)
            return [
                activeObservation(
                    meetingID: meetingID,
                    offset: start + 2,
                    name: names[index],
                    score: 0.94,
                    sequence: index * 3 + 1
                ),
                activeObservation(
                    meetingID: meetingID,
                    offset: start + 4,
                    name: names[index],
                    score: 0.92,
                    sequence: index * 3 + 2
                ),
                activeObservation(
                    meetingID: meetingID,
                    offset: start + 6,
                    name: names[index],
                    score: 0.90,
                    sequence: index * 3 + 3
                ),
            ]
        }

        let suggestions = service.suggestions(
            meetingID: meetingID,
            attendeeNames: names,
            transcript: StoredTranscript(speakers: speakers, segments: segments),
            observations: observations,
            dismissed: []
        )

        #expect(suggestions.count == 6)
        #expect(Set(suggestions.map(\.proposedName)) == Set(names))
    }

    @Test
    func bankMatchedSpeakerIsNeverReplacedByScreenSuggestion() {
        let service = SpeakerIdentitySuggestionService()
        let meetingID = UUID()
        let transcript = StoredTranscript(
            speakers: [
                TranscriptSpeaker(
                    id: "speaker-1",
                    displayName: "Known Alice",
                    labelSource: .bankMatched,
                    matchedKnownSpeakerID: "known-alice"
                )
            ],
            segments: [
                TranscriptSegment(text: "Hello", startTime: 0, endTime: 10, speakerID: "speaker-1")
            ]
        )
        let observations = (1...4).map {
            activeObservation(
                meetingID: meetingID,
                offset: TimeInterval($0 * 2),
                name: "Masha",
                score: 0.95,
                sequence: $0
            )
        }

        #expect(service.suggestions(
            meetingID: meetingID,
            attendeeNames: ["Masha"],
            transcript: transcript,
            observations: observations,
            dismissed: []
        ).isEmpty)
    }
}

private func activeObservation(
    meetingID: UUID,
    offset: TimeInterval,
    name: String,
    score: Double,
    sequence: Int
) -> ScreenObservation {
    ScreenObservation(
        meetingID: meetingID,
        capturedAtOffset: offset,
        imageRelativePath: String(format: "screen-observations/%04d.jpg", sequence),
        thumbnailRelativePath: String(format: "screen-observations/%04d-thumb.jpg", sequence),
        activeTile: ScreenTileObservation(
            boundingBox: UnitRect(x: 0, y: 0, width: 1, height: 1),
            matchedName: name,
            highlightScore: score
        )
    )
}
