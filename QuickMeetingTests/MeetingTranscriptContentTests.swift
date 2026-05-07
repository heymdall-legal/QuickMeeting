import Foundation
import Testing
@testable import QuickMeeting
#if canImport(AppKit)
import AppKit
#endif

struct MeetingTranscriptContentTests {
    @Test
    func transcriptReloadKeyChangesWhenTranscriptPathChanges() throws {
        let meeting = Meeting(
            title: "Sync",
            startedAt: Date(timeIntervalSince1970: 1_714_561_200),
            status: .recorded,
            audioFilePath: "/tmp/audio.wav"
        )
        let initialKey = meetingTranscriptReloadKey(for: meeting)

        meeting.completeTranscription(
            transcript: StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(text: "Transcript", speakerID: "speaker-1")]
            ),
            transcriptPreview: "Transcript"
        )

        #expect(meetingTranscriptReloadKey(for: meeting) != initialKey)
    }

    @Test
    func audioReloadKeyDoesNotChangeWhenOnlyTranscriptChanges() throws {
        let meeting = Meeting(
            title: "Sync",
            startedAt: Date(timeIntervalSince1970: 1_714_561_200),
            status: .recorded,
            audioFilePath: "/tmp/audio.wav"
        )
        let initialKey = meetingAudioReloadKey(for: meeting)

        meeting.completeTranscription(
            transcript: StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
                segments: [TranscriptSegment(text: "Transcript", speakerID: "speaker-1")]
            ),
            transcriptPreview: "Transcript"
        )

        #expect(meetingAudioReloadKey(for: meeting) == initialKey)
    }

    @Test
    func missingTranscriptReturnsNotAvailable() throws {
        let content = loadMeetingTranscriptContent(from: nil)

        #expect(content == .notAvailable)
    }

    @Test
    func storedTranscriptLoadsStructuredDisplayContent() {
        let content = loadMeetingTranscriptContent(
            from: StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Masha")],
                segments: [TranscriptSegment(text: "  Hello world  ", startTime: 5, endTime: 7, speakerID: "speaker-1")]
            )
        )

        guard case .transcript(let display) = content else {
            Issue.record("Expected transcript display content")
            return
        }

        #expect(display.speakers == [TranscriptSpeaker(id: "speaker-1", displayName: "Masha")])
        #expect(display.segments.map(\.text) == ["Hello world"])
        #expect(display.segments.map(\.startTime) == [5])
        #expect(display.segments.map(\.endTime) == [7])
        #expect(display.segments.map(\.speakerID) == ["speaker-1"])
    }

    @Test
    func meetingStoredTranscriptSortsPersistedSegmentsChronologically() throws {
        let meeting = Meeting(
            title: "Sync",
            startedAt: Date(timeIntervalSince1970: 1_714_561_200),
            status: .completed,
            audioFilePath: "/tmp/audio.wav",
            transcriptSpeakers: [PersistedTranscriptSpeaker(id: "speaker-1", displayName: "Masha")],
            transcriptSegments: [
                PersistedTranscriptSegment(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    text: "Second sentence",
                    startTime: 12,
                    endTime: 18,
                    speakerID: "speaker-1"
                ),
                PersistedTranscriptSegment(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    text: "First sentence",
                    startTime: 3,
                    endTime: 9,
                    speakerID: "speaker-1"
                ),
            ]
        )

        let transcript = try #require(meeting.storedTranscript)

        #expect(transcript.segments.map(\.text) == ["First sentence", "Second sentence"])
        let content = loadMeetingTranscriptContent(from: transcript)
        guard case .transcript(let display) = content else {
            Issue.record("Expected transcript display content")
            return
        }

        #expect(display.speakers == [TranscriptSpeaker(id: "speaker-1", displayName: "Masha")])
        #expect(display.segments.map(\.text) == ["First sentence", "Second sentence"])
        #expect(display.segments.map(\.startTime) == [3, 12])
        #expect(display.segments.map(\.endTime) == [9, 18])
        #expect(display.segments.map(\.speakerID) == ["speaker-1", "speaker-1"])
    }

    @Test
    func loadMeetingTranscriptSpeakersReturnsAvailableSpeakersFromStoredTranscript() {
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
        )

        let speakers = loadMeetingTranscriptSpeakers(from: transcript)

        #expect(speakers == .available([TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")]))
    }

    @Test
    func displayRunsGroupConsecutiveSegmentsByResolvedSpeaker() {
        let display = MeetingTranscriptDisplay(
            speakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
                TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2")
            ],
            segments: [
                TranscriptSegment(text: "First", startTime: 0, endTime: 1, speakerID: "speaker-1"),
                TranscriptSegment(text: "Second", startTime: 2, endTime: 3, speakerID: "speaker-1"),
                TranscriptSegment(text: "Third", startTime: 4, endTime: 5, speakerID: "speaker-2"),
                TranscriptSegment(text: "Fourth", startTime: 6, endTime: 7, speakerID: nil)
            ]
        )

        let runs = transcriptDisplayRuns(from: display)

        #expect(runs.map(\.speakerName) == ["Speaker 1", "Speaker 2", nil])
        #expect(runs.map { $0.segments.map(\.text) } == [["First", "Second"], ["Third"], ["Fourth"]])
        #expect(runs.map { $0.segments.map(\.startTime) } == [[0, 2], [4], [6]])
    }

    @Test
    func segmentTimestampTextUsesMinuteSecondFormatting() {
        #expect(segmentTimestampText(for: 0) == "0:00")
        #expect(segmentTimestampText(for: 9) == "0:09")
        #expect(segmentTimestampText(for: 65) == "1:05")
        #expect(segmentTimestampText(for: 3_661) == "1:01:01")
    }

    #if canImport(AppKit)
    @Test
    func transcriptAttributedStringBuildsSpeakerHeadingsAndBodyText() {
        let display = MeetingTranscriptDisplay(
            speakers: [
                TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
                TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2")
            ],
            segments: [
                TranscriptSegment(text: "some words", startTime: 0, endTime: 1, speakerID: "speaker-1"),
                TranscriptSegment(text: "that is very important", startTime: 2, endTime: 3, speakerID: "speaker-1"),
                TranscriptSegment(text: "and so on", startTime: 4, endTime: 5, speakerID: "speaker-2")
            ]
        )

        let attributedString = makeTranscriptAttributedString(from: display)

        #expect(
            attributedString.string
                == "Speaker 1\nsome words\nthat is very important\n\nSpeaker 2\nand so on"
        )
    }

    @Test
    func transcriptAttributedStringUsesHeadlineWeightForSpeakerHeadings() throws {
        let display = MeetingTranscriptDisplay(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [TranscriptSegment(text: "Line one", startTime: 0, endTime: 1, speakerID: "speaker-1")]
        )
        let attributedString = makeTranscriptAttributedString(from: display)
        let headingFont = try #require(attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(headingFont.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test
    func transcriptLayoutIncludesTimestampAnchorForEachSegment() {
        let display = MeetingTranscriptDisplay(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [
                TranscriptSegment(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    text: "First line",
                    startTime: 0,
                    endTime: 1,
                    speakerID: "speaker-1"
                ),
                TranscriptSegment(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    text: "Second line",
                    startTime: 10,
                    endTime: 11,
                    speakerID: "speaker-1"
                )
            ]
        )

        let layout = makeTranscriptLayout(from: display)

        #expect(layout.attributedString.string == "Speaker 1\nFirst line\nSecond line")
        #expect(layout.timestampAnchors.map(\.timestampText) == ["0:00", "0:10"])
        #expect(layout.timestampAnchors.map(\.segmentID.uuidString) == [
            "11111111-1111-1111-1111-111111111111",
            "22222222-2222-2222-2222-222222222222"
        ])
    }

    @Test
    func transcriptDocumentViewReportsNonZeroContentSizeAfterUpdate() {
        let display = MeetingTranscriptDisplay(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [
                TranscriptSegment(text: "First line", startTime: 0, endTime: 1, speakerID: "speaker-1"),
                TranscriptSegment(text: "Second line", startTime: 10, endTime: 11, speakerID: "speaker-1")
            ]
        )

        let documentView = TranscriptDocumentView()
        documentView.update(display: display, showSegmentTimes: true, availableWidth: 500)

        #expect(documentView.frame.height > 0)
        #expect(documentView.frame.width == 500)
        #expect(documentView.timestampStrings == ["0:00", "0:10"])
        #expect(documentView.transcriptString == "Speaker 1\nFirst line\nSecond line")
        #expect(documentView.isTimestampContainerFlipped == true)
    }

    @Test
    func transcriptDocumentViewPositionsTimestampsUsingWrappedTextLayout() {
        let display = MeetingTranscriptDisplay(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [
                TranscriptSegment(
                    text: "This is a very long first segment that should wrap onto multiple visual lines in the transcript view.",
                    startTime: 0,
                    endTime: 1,
                    speakerID: "speaker-1"
                ),
                TranscriptSegment(
                    text: "Second segment",
                    startTime: 10,
                    endTime: 11,
                    speakerID: "speaker-1"
                )
            ]
        )

        let documentView = TranscriptDocumentView()
        documentView.update(display: display, showSegmentTimes: true, availableWidth: 260)

        #expect(documentView.timestampStrings == ["0:00", "0:10"])
        #expect(documentView.timestampOrigins.count == 2)
        #expect(documentView.timestampOrigins[1] > documentView.timestampOrigins[0] + 40)
    }
    #endif
}
