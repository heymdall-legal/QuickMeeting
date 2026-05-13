import Foundation

func renderMeetingTranscriptExportMarkdown(
    meeting: Meeting,
    transcript: StoredTranscript
) -> String {
    let speakerNames = Dictionary(uniqueKeysWithValues: transcript.speakers.map { ($0.id, $0.displayName) })
    let title = transcriptExportTitle(for: meeting)
    let dateText = transcriptExportDateText(for: meeting.startedAt)
    let durationText = transcriptExportDurationText(meeting.duration)

    let sections = transcript.segments.reduce(into: [(speakerName: String, lines: [String])]()) { result, segment in
        let line = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            return
        }

        let speakerName = segment.speakerID.flatMap { speakerNames[$0] } ?? "Speaker"
        if result.last?.speakerName == speakerName {
            result[result.count - 1].lines.append(line)
        } else {
            result.append((speakerName: speakerName, lines: [line]))
        }
    }
    .map { section in
        "## \(section.speakerName)\n" + section.lines.joined(separator: "\n\n")
    }

    return ([
        "# \(title)",
        "Date: **\(dateText)**",
        "Duration: **\(durationText)**"
    ] + sections).joined(separator: "\n\n")
}

func transcriptExportDurationText(_ duration: TimeInterval?) -> String {
    guard let duration else {
        return "00:00"
    }

    let totalMinutes = max(Int(duration.rounded(.down)) / 60, 0)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return String(format: "%02d:%02d", hours, minutes)
}

private func transcriptExportTitle(for meeting: Meeting) -> String {
    let trimmedTitle = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedTitle.isEmpty ? "Untitled Meeting" : trimmedTitle
}

func transcriptExportDateText(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}
