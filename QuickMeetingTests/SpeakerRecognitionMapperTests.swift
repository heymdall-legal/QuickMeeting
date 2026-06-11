import Foundation
import Testing
@testable import QuickMeeting

struct SpeakerRecognitionMapperTests {
    @Test
    func mapperAppliesBankMatchedNameWhenProbabilityExceedsThreshold() {
        let mapper = SpeakerRecognitionMapper()
        let speakers = mapper.makeTranscriptSpeakers(
            sidecarSpeakers: [
                SidecarCompletedSpeaker(
                    id: "SPEAKER_00",
                    matchedID: "known-alice",
                    probability: 0.91,
                    centroid: [0.1, 0.2]
                )
            ],
            segments: [
                SidecarCompletedSegment(
                    speaker: "SPEAKER_00",
                    start: 0,
                    end: 1,
                    text: "Hello"
                )
            ],
            knownSpeakerNamesByID: ["known-alice": "Alice"]
        )

        #expect(speakers == [
            TranscriptSpeaker(
                id: "SPEAKER_00",
                displayName: "Alice",
                labelSource: .bankMatched,
                matchedKnownSpeakerID: "known-alice",
                centroid: [0.1, 0.2]
            )
        ])
    }
}
