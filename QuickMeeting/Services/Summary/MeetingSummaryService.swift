import Foundation

protocol MeetingSummaryServicing {
    func summarize(meetingID: UUID) async throws -> String
}

enum MeetingSummaryServiceError: LocalizedError, Equatable {
    case transcriptMissing
    case transcriptEmpty
    case settingsIncomplete
    case invalidBaseURL
    case requestFailed(statusCode: Int, message: String?)
    case responseInvalid

    var errorDescription: String? {
        switch self {
        case .transcriptMissing:
            return "Transcript data is unavailable."
        case .transcriptEmpty:
            return "Transcript does not contain any usable text."
        case .settingsIncomplete:
            return "Before generating a summary, open Settings and fill in the summary API base URL, API token, model, and prompt template."
        case .invalidBaseURL:
            return "Summary API base URL is invalid."
        case .requestFailed(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Summary request failed (\(statusCode)): \(message)"
            }
            return "Summary request failed with status \(statusCode)."
        case .responseInvalid:
            return "Summary response did not contain usable text."
        }
    }
}

protocol MeetingSummaryTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionMeetingSummaryTransport: MeetingSummaryTransporting {
    let session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MeetingSummaryServiceError.responseInvalid
        }
        return (data, httpResponse)
    }
}

struct MeetingSummaryService: MeetingSummaryServicing {
    private let meetingStore: MeetingStore
    private let settingsStore: any MeetingSummarySettingsStoring
    private let transport: any MeetingSummaryTransporting

    init(
        meetingStore: MeetingStore,
        settingsStore: (any MeetingSummarySettingsStoring)? = nil,
        transport: (any MeetingSummaryTransporting)? = nil
    ) {
        self.meetingStore = meetingStore
        self.settingsStore = settingsStore ?? MeetingSummarySettingsStore()
        self.transport = transport ?? URLSessionMeetingSummaryTransport()
    }

    func summarize(meetingID: UUID) async throws -> String {
        let meeting = try meetingStore.fetchMeeting(id: meetingID)
        guard let transcript = meeting.storedTranscript else {
            throw MeetingSummaryServiceError.transcriptMissing
        }
        guard let settings = settingsStore.validatedSettings() else {
            throw MeetingSummaryServiceError.settingsIncomplete
        }

        let transcriptBody = renderMeetingTranscriptExportMarkdownBody(meeting: meeting, transcript: transcript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcriptBody.isEmpty else {
            throw MeetingSummaryServiceError.transcriptEmpty
        }

        let prompt = settings.promptTemplate
            .replacingOccurrences(of: "{text}", with: transcriptBody)
            .replacingOccurrences(of: "{date}", with: summaryPromptDateText(for: meeting.startedAt))

        let request = try makeRequest(settings: settings, prompt: prompt)
        let (data, response) = try await transport.send(request)

        guard (200 ..< 300).contains(response.statusCode) else {
            let message = String(data: data.prefix(200), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MeetingSummaryServiceError.requestFailed(statusCode: response.statusCode, message: message)
        }

        let payload = try JSONDecoder().decode(MeetingSummaryResponse.self, from: data)
        guard
            let content = payload.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
            !content.isEmpty
        else {
            throw MeetingSummaryServiceError.responseInvalid
        }

        return content
    }

    private func makeRequest(
        settings: ValidatedMeetingSummarySettings,
        prompt: String
    ) throws -> URLRequest {
        guard let url = normalizedCompletionsURL(from: settings.baseURL) else {
            throw MeetingSummaryServiceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            authHeaderValue(for: settings),
            forHTTPHeaderField: settings.authHeaderName
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("opencode/1.17.7 ai-sdk/provider-utils/4.0.23 runtime/bun/1.3.14", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            MeetingSummaryRequest(
                model: settings.modelName,
                messages: [.init(role: "user", content: prompt)],
                stream: false
            )
        )
        return request
    }

    private func authHeaderValue(for settings: ValidatedMeetingSummarySettings) -> String {
        guard settings.authHeaderName.caseInsensitiveCompare("Authorization") == .orderedSame else {
            return settings.authToken
        }

        if settings.authToken.range(of: "Bearer ", options: [.anchored, .caseInsensitive]) != nil {
            return settings.authToken
        }
        return "Bearer \(settings.authToken)"
    }
}

private struct MeetingSummaryRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
}

private struct MeetingSummaryResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private func normalizedCompletionsURL(from baseURL: String) -> URL? {
    guard var url = URL(string: baseURL) else {
        return nil
    }

    if url.path.hasSuffix("/chat/completions") {
        return url
    }

    if url.path.hasSuffix("/v1") {
        url.appendPathComponent("chat")
        url.appendPathComponent("completions")
        return url
    }

    url.appendPathComponent("v1")
    url.appendPathComponent("chat")
    url.appendPathComponent("completions")
    return url
}

func summaryPromptDateText(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
