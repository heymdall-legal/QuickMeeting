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

    @Test
    func splitTranscriptTextReturnsTrimmedLeftAndRightSides() {
        let split = splitTranscriptText("Hello Masha", cursorOffset: 5)

        #expect(split == TranscriptTextSplit(left: "Hello", right: "Masha"))
    }

    @Test
    func splitTranscriptTextRejectsCursorAtStartOrEnd() {
        #expect(splitTranscriptText("Hello", cursorOffset: 0) == nil)
        #expect(splitTranscriptText("Hello", cursorOffset: 5) == nil)
    }

    @Test
    func splitTranscriptTextRejectsWhitespaceOnlySide() {
        #expect(splitTranscriptText("Hello   ", cursorOffset: 5) == nil)
        #expect(splitTranscriptText("   Hello", cursorOffset: 3) == nil)
    }

    @Test
    func mergedTranscriptTextJoinsWithOneNewline() {
        #expect(mergedTranscriptText(previous: "First\n", current: "\nSecond") == "First\nSecond")
    }
}
