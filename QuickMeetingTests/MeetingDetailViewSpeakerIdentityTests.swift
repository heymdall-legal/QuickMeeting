import Testing
@testable import QuickMeeting

struct MeetingDetailViewSpeakerIdentityTests {
    @Test
    func explicitSpeakerIDUsesMatchingTranscriptSpeaker() {
        let identity = resolvedTranscriptBubbleSpeakerIdentity(
            segment: TranscriptSegment(text: "Hello", speakerID: "speaker-2"),
            segmentIndex: 0,
            transcriptSpeakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Masha"),
                TranscriptSpeaker(id: "speaker-2", displayName: "Sasha")
            ]
        )

        #expect(identity == ResolvedTranscriptBubbleSpeakerIdentity(id: "speaker-2", displayName: "Sasha"))
    }

    @Test
    func placeholderFirstSpeakerResolvesToFirstPersistedTranscriptSpeaker() {
        let identity = resolvedTranscriptBubbleSpeakerIdentity(
            segment: TranscriptSegment(text: "Hello", speakerID: nil),
            segmentIndex: 0,
            transcriptSpeakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Masha"),
                TranscriptSpeaker(id: "speaker-2", displayName: "Sasha")
            ]
        )

        #expect(identity == ResolvedTranscriptBubbleSpeakerIdentity(id: "speaker-1", displayName: "Masha"))
    }

    @Test
    func missingSpeakerFallsBackToSyntheticPlaceholderIdentity() {
        let identity = resolvedTranscriptBubbleSpeakerIdentity(
            segment: TranscriptSegment(text: "Hello", speakerID: nil),
            segmentIndex: 2,
            transcriptSpeakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Masha")
            ]
        )

        #expect(identity == ResolvedTranscriptBubbleSpeakerIdentity(id: "speaker-2", displayName: "Speaker 3"))
    }
}
