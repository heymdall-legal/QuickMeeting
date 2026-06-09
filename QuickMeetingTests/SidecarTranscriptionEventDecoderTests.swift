import Foundation
import Testing
@testable import QuickMeeting

struct SidecarTranscriptionEventDecoderTests {
    @Test
    func decodesCompletedEventWithSpeakersAndSegments() throws {
        let line = """
        {"status":"completed","speakers":[{"id":"SPEAKER_00","matched_id":null,"probability":null,"centroid":null}],"segments":[{"speaker":"SPEAKER_00","start":0.0,"end":2.481,"text":"Hello everyone"}]}
        """

        let event = try SidecarTranscriptionEventDecoder().decode(line: line)

        guard case .completed(let payload) = event else {
            Issue.record("Expected completed event")
            return
        }

        #expect(payload.speakers.map(\.id) == ["SPEAKER_00"])
        #expect(payload.segments.map(\.text) == ["Hello everyone"])
    }

    @Test
    func returnsNilForMalformedJsonLine() throws {
        let event = try SidecarTranscriptionEventDecoder().decode(line: "not json")
        #expect(event == nil)
    }

    @Test
    func decodesDiarizationProgressAsPercentInteger() throws {
        let line = #"{"status":"diarization","step":"segmentation","percent":15}"#

        let event = try SidecarTranscriptionEventDecoder().decode(line: line)

        guard case .diarization(let payload) = event else {
            Issue.record("Expected diarization event")
            return
        }

        #expect(payload.step == "segmentation")
        #expect(payload.percent == 15)
    }
}
