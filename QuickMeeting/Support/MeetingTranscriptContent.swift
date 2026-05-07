import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum MeetingTranscriptContent: Equatable {
    case text(String)
    case notAvailable
    case unavailable(message: String)
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

    let markdown = TranscriptionArtifactWriter().renderMarkdown(from: transcript)
    guard !markdown.isEmpty else {
        return .notAvailable
    }

    return .text(markdown)
}

func loadMeetingTranscriptSpeakers(from transcript: StoredTranscript?) -> MeetingTranscriptSpeakersContent {
    guard let transcript else {
        return .unavailable
    }

    return .available(transcript.speakers)
}

#if canImport(AppKit)
func makeTranscriptAttributedString(from transcript: String) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 6

    return NSAttributedString(
        string: transcript,
        attributes: [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    )
}
#endif
