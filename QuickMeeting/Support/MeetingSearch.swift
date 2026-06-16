import Foundation

nonisolated struct MeetingSearchDocument: Equatable, Sendable {
    let id: UUID
    let title: String
    let speakerNames: [String]
    let segmentTexts: [String]
}

func normalizedMeetingSearchQuery(_ query: String) -> String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
}

func meetingSearchDocument(for meeting: Meeting) -> MeetingSearchDocument {
    MeetingSearchDocument(
        id: meeting.id,
        title: meeting.title,
        speakerNames: meeting.transcriptSpeakers.map(\.displayName),
        segmentTexts: meeting.transcriptSegments.map(\.text)
    )
}

func meetingSearchDocumentMatchesSearch(_ document: MeetingSearchDocument, query: String) -> Bool {
    let normalizedQuery = normalizedMeetingSearchQuery(query)
    guard !normalizedQuery.isEmpty else {
        return true
    }

    func containsQuery(_ value: String) -> Bool {
        value.range(of: normalizedQuery, options: .caseInsensitive) != nil
    }

    if containsQuery(document.title) {
        return true
    }

    if document.speakerNames.contains(where: {
        !QMSpeakerPalette.isUnnamed($0) && containsQuery($0)
    }) {
        return true
    }

    return document.segmentTexts.contains(where: containsQuery)
}

func searchMeetingIDs(in documents: [MeetingSearchDocument], query: String) -> Set<UUID> {
    Set(
        documents.lazy
            .filter { meetingSearchDocumentMatchesSearch($0, query: query) }
            .map(\.id)
    )
}

func meetingMatchesSearch(_ meeting: Meeting, query: String) -> Bool {
    meetingSearchDocumentMatchesSearch(meetingSearchDocument(for: meeting), query: query)
}
