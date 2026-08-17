import Foundation
import Testing
@testable import QuickMeeting

struct SpeakerWordAlignerTests {
    @Test
    func maximumOverlapWinsAndMidpointBreaksEqualOverlap() {
        let word = TimedWord(text: "hello", startTime: 1, endTime: 2, confidence: nil)
        #expect(SpeakerWordAligner.speakerID(for: word, intervals: [
            SpeakerInterval(speakerID: "A", startTime: 0.9, endTime: 1.5),
            SpeakerInterval(speakerID: "B", startTime: 1.5, endTime: 2.1),
        ]) == "B")
    }

    @Test
    func ambiguousOverlapAndDistantGapStayUnknown() {
        let overlapped = TimedWord(text: "hello", startTime: 1, endTime: 2, confidence: nil)
        #expect(SpeakerWordAligner.speakerID(for: overlapped, intervals: [
            SpeakerInterval(speakerID: "A", startTime: 1, endTime: 2),
            SpeakerInterval(speakerID: "B", startTime: 1, endTime: 2),
        ]) == nil)

        let inGap = TimedWord(text: "gap", startTime: 3, endTime: 3.1, confidence: nil)
        #expect(SpeakerWordAligner.speakerID(for: inGap, intervals: [
            SpeakerInterval(speakerID: "A", startTime: 0, endTime: 1),
        ]) == nil)
    }

    @Test
    func uniqueSpeakerWithinBoundedGapToleranceIsUsed() {
        let word = TimedWord(text: "near", startTime: 1.1, endTime: 1.2, confidence: nil)
        #expect(SpeakerWordAligner.speakerID(for: word, intervals: [
            SpeakerInterval(speakerID: "A", startTime: 0, endTime: 1),
        ]) == "A")
    }
}
