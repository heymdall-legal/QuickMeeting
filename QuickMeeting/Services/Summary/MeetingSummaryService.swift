import Foundation

protocol MeetingSummaryServicing {
    func summarize(meetingID: UUID) async throws -> String
}

nonisolated struct LLMTranscriptCorrectionResult: Sendable, Equatable {
    let transcript: StoredTranscript
    let modelName: String
}

nonisolated protocol TranscriptLLMCorrecting {
    func correct(
        transcript: StoredTranscript,
        glossaryTerms: [TranscriptionGlossaryTerm]
    ) async throws -> LLMTranscriptCorrectionResult
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

enum LLMTranscriptCorrectionError: LocalizedError, Equatable {
    case settingsIncomplete
    case requestFailed(statusCode: Int, message: String?)
    case responseInvalid

    var errorDescription: String? {
        switch self {
        case .settingsIncomplete:
            return "LLM correction settings are incomplete."
        case .requestFailed(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Correction request failed (\(statusCode)): \(message)"
            }
            return "Correction request failed with status \(statusCode)."
        case .responseInvalid:
            return "Correction response did not contain usable segment JSON."
        }
    }
}

protocol MeetingSummaryTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionMeetingSummaryTransport: MeetingSummaryTransporting {
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

        let request = try Self.makeRequest(settings: settings, prompt: prompt)
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

    fileprivate static func makeRequest(
        settings: ValidatedMeetingSummarySettings,
        prompt: String
    ) throws -> URLRequest {
        guard let url = normalizedCompletionsURL(from: settings.baseURL) else {
            throw MeetingSummaryServiceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            authHeaderValue(
                authHeaderName: settings.authHeaderName,
                authToken: settings.authToken
            ),
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

    nonisolated fileprivate static func makeCorrectionRequest(
        settings: ValidatedLLMCorrectionSettings,
        prompt: String
    ) throws -> URLRequest {
        guard let url = normalizedCompletionsURL(from: settings.baseURL) else {
            throw MeetingSummaryServiceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            authHeaderValue(
                authHeaderName: settings.authHeaderName,
                authToken: settings.authToken
            ),
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

    nonisolated fileprivate static func authHeaderValue(authHeaderName: String, authToken: String) -> String {
        guard authHeaderName.caseInsensitiveCompare("Authorization") == .orderedSame else {
            return authToken
        }

        if authToken.range(of: "Bearer ", options: [.anchored, .caseInsensitive]) != nil {
            return authToken
        }
        return "Bearer \(authToken)"
    }
}

nonisolated struct LLMTranscriptCorrectionService: TranscriptLLMCorrecting {
    private let settingsStore: any MeetingSummarySettingsStoring
    private let transport: any MeetingSummaryTransporting

    init(
        settingsStore: (any MeetingSummarySettingsStoring)? = nil,
        transport: (any MeetingSummaryTransporting)? = nil
    ) {
        self.settingsStore = settingsStore ?? MeetingSummarySettingsStore()
        self.transport = transport ?? URLSessionMeetingSummaryTransport()
    }

    func correct(
        transcript: StoredTranscript,
        glossaryTerms: [TranscriptionGlossaryTerm]
    ) async throws -> LLMTranscriptCorrectionResult {
        guard let settings = settingsStore.validatedCorrectionSettings() else {
            throw LLMTranscriptCorrectionError.settingsIncomplete
        }

        let prompt = settings.promptTemplate
            .replacingOccurrences(of: "{text}", with: correctionSegmentJSON(for: transcript))
            .replacingOccurrences(of: "{glossary}", with: correctionGlossaryText(glossaryTerms))

        let request = try MeetingSummaryService.makeCorrectionRequest(settings: settings, prompt: prompt)
        let (data, response) = try await transport.send(request)

        guard (200 ..< 300).contains(response.statusCode) else {
            let message = String(data: data.prefix(200), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LLMTranscriptCorrectionError.requestFailed(statusCode: response.statusCode, message: message)
        }

        let payload = try JSONDecoder().decode(MeetingSummaryResponse.self, from: data)
        guard
            let content = payload.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
            !content.isEmpty,
            let correction = decodeCorrectionPayload(from: content)
        else {
            throw LLMTranscriptCorrectionError.responseInvalid
        }

        let replacementTextByID = Dictionary(uniqueKeysWithValues: correction.segments.map { ($0.id.lowercased(), $0.text) })
        let correctedSegments = transcript.segments.map { segment in
            guard
                let replacement = replacementTextByID[segment.id.uuidString.lowercased()],
                !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return segment
            }
            return TranscriptSegment(
                id: segment.id,
                text: replacement.trimmingCharacters(in: .newlines),
                startTime: segment.startTime,
                endTime: segment.endTime,
                speakerID: segment.speakerID
            )
        }

        return LLMTranscriptCorrectionResult(
            transcript: StoredTranscript(speakers: transcript.speakers, segments: correctedSegments),
            modelName: settings.modelName
        )
    }
}

nonisolated private struct MeetingSummaryRequest: Encodable {
    nonisolated struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
}

nonisolated private struct MeetingSummaryResponse: Decodable {
    nonisolated struct Choice: Decodable {
        nonisolated struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

nonisolated private struct LLMCorrectionPayload: Decodable {
    nonisolated struct Segment: Decodable {
        let id: String
        let text: String
    }

    let segments: [Segment]
}

nonisolated private func correctionSegmentJSON(for transcript: StoredTranscript) -> String {
    let payload = transcript.segments.map { segment in
        [
            "id": segment.id.uuidString,
            "text": segment.text,
        ]
    }
    guard
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
        let text = String(data: data, encoding: .utf8)
    else {
        return "[]"
    }
    return text
}

nonisolated private func correctionGlossaryText(_ terms: [TranscriptionGlossaryTerm]) -> String {
    let lines = terms
        .filter { !$0.normalizedText.isEmpty }
        .map { term -> String in
            let aliases = term.normalizedAliases
            if aliases.isEmpty {
                return "- \(term.normalizedText)"
            }
            return "- \(term.normalizedText) (aliases: \(aliases.joined(separator: ", ")))"
        }
    return lines.isEmpty ? "No glossary terms configured." : lines.joined(separator: "\n")
}

nonisolated private func decodeCorrectionPayload(from content: String) -> LLMCorrectionPayload? {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    let jsonText: String
    if trimmed.hasPrefix("```") {
        jsonText = trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        jsonText = trimmed
    }
    guard let data = jsonText.data(using: .utf8) else {
        return nil
    }
    return try? JSONDecoder().decode(LLMCorrectionPayload.self, from: data)
}

nonisolated private func normalizedCompletionsURL(from baseURL: String) -> URL? {
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
