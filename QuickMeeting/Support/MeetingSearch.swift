import Foundation

func meetingMatchesSearch(_ meeting: Meeting, query: String) -> Bool {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else {
        return true
    }

    func containsQuery(_ value: String) -> Bool {
        value.range(of: normalizedQuery, options: .caseInsensitive) != nil
    }

    if containsQuery(meeting.title) {
        return true
    }

    guard let transcript = meeting.storedTranscript else {
        return false
    }

    if transcript.speakers.contains(where: {
        !QMSpeakerPalette.isUnnamed($0.displayName)
            && containsQuery($0.displayName)
    }) {
        return true
    }

    return transcript.segments.contains(where: { containsQuery($0.text) })
}
