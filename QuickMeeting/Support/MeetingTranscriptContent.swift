import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum MeetingTranscriptContent: Equatable {
    case transcript(MeetingTranscriptDisplay)
    case notAvailable
    case unavailable(message: String)
}

struct MeetingTranscriptDisplay: Equatable {
    let speakers: [TranscriptSpeaker]
    let segments: [TranscriptSegment]
}

struct TranscriptDisplayRun: Equatable {
    let speakerName: String?
    var segments: [TranscriptSegment]
}

enum MeetingTranscriptSpeakersContent: Equatable {
    case available([TranscriptSpeaker])
    case unavailable
}

func meetingTranscriptReloadKey(for meeting: Meeting) -> String {
    [
        meeting.id.uuidString,
        String(meeting.transcriptSpeakers.count),
        String(meeting.transcriptSegments.count),
        String(meeting.updatedAt.timeIntervalSinceReferenceDate)
    ].joined(separator: "|")
}

func meetingAudioReloadKey(for meeting: Meeting) -> String {
    [
        meeting.id.uuidString,
        meeting.audioFilePath
    ].joined(separator: "|")
}

func loadMeetingTranscriptContent(from transcript: StoredTranscript?) -> MeetingTranscriptContent {
    guard let transcript else {
        return .notAvailable
    }

    let trimmedSegments = transcript.segments.compactMap { segment -> TranscriptSegment? in
        let trimmedText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        return TranscriptSegment(
            id: segment.id,
            text: trimmedText,
            startTime: segment.startTime,
            endTime: segment.endTime,
            speakerID: segment.speakerID
        )
    }

    guard !trimmedSegments.isEmpty else {
        return .notAvailable
    }

    return .transcript(
        MeetingTranscriptDisplay(
            speakers: transcript.speakers,
            segments: trimmedSegments
        )
    )
}

func loadMeetingTranscriptSpeakers(from transcript: StoredTranscript?) -> MeetingTranscriptSpeakersContent {
    guard let transcript else {
        return .unavailable
    }

    return .available(transcript.speakers)
}

func transcriptDisplayRuns(from display: MeetingTranscriptDisplay) -> [TranscriptDisplayRun] {
    let speakersByID = Dictionary(uniqueKeysWithValues: display.speakers.map { ($0.id, $0.displayName) })
    var runs = [TranscriptDisplayRun]()

    for segment in display.segments {
        let speakerName = segment.speakerID.flatMap { speakersByID[$0] }

        if let lastIndex = runs.indices.last, runs[lastIndex].speakerName == speakerName {
            runs[lastIndex].segments.append(segment)
        } else {
            runs.append(TranscriptDisplayRun(speakerName: speakerName, segments: [segment]))
        }
    }

    return runs
}

func segmentTimestampText(for startTime: TimeInterval) -> String {
    let totalSeconds = max(Int(startTime.rounded(.down)), 0)
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    return String(format: "%d:%02d", minutes, seconds)
}

#if canImport(AppKit)
struct TranscriptTimestampAnchor: Equatable {
    let segmentID: UUID
    let timestampText: String
    let characterRange: NSRange
}

struct TranscriptLayout: Equatable {
    let attributedString: NSAttributedString
    let timestampAnchors: [TranscriptTimestampAnchor]
}

func makeTranscriptLayout(from display: MeetingTranscriptDisplay) -> TranscriptLayout {
    let transcript = NSMutableAttributedString()
    let runs = transcriptDisplayRuns(from: display)
    var timestampAnchors = [TranscriptTimestampAnchor]()

    let bodyParagraphStyle = NSMutableParagraphStyle()
    bodyParagraphStyle.lineSpacing = 6

    let headingParagraphStyle = NSMutableParagraphStyle()
    headingParagraphStyle.lineSpacing = 6

    let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.preferredFont(forTextStyle: .body),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: bodyParagraphStyle
    ]

    let headingAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.preferredFont(forTextStyle: .headline),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: headingParagraphStyle
    ]

    for (runIndex, run) in runs.enumerated() {
        if let speakerName = run.speakerName {
            transcript.append(NSAttributedString(string: speakerName + "\n", attributes: headingAttributes))
        }

        for (segmentIndex, segment) in run.segments.enumerated() {
            let segmentStart = transcript.length
            transcript.append(NSAttributedString(string: segment.text, attributes: bodyAttributes))

            if let startTime = segment.startTime {
                timestampAnchors.append(
                    TranscriptTimestampAnchor(
                        segmentID: segment.id,
                        timestampText: segmentTimestampText(for: startTime),
                        characterRange: NSRange(location: segmentStart, length: max(segment.text.count, 1))
                    )
                )
            }

            let isLastSegmentInRun = segmentIndex == run.segments.count - 1
            let isLastRun = runIndex == runs.count - 1

            if !isLastSegmentInRun {
                transcript.append(NSAttributedString(string: "\n", attributes: bodyAttributes))
            } else if !isLastRun {
                transcript.append(NSAttributedString(string: "\n\n", attributes: bodyAttributes))
            }
        }
    }

    return TranscriptLayout(
        attributedString: transcript,
        timestampAnchors: timestampAnchors
    )
}

func makeTranscriptAttributedString(from display: MeetingTranscriptDisplay) -> NSAttributedString {
    makeTranscriptLayout(from: display).attributedString
}
#endif
