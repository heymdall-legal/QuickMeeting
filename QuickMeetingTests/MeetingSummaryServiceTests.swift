import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

struct MeetingSummaryServiceTests {
    @Test
    func summarizeBuildsOpenAICompatibleRequestAndReturnsTrimmedContent() async throws {
        let harness = try MeetingSummaryServiceHarness()
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Alice")],
                segments: [TranscriptSegment(text: "We shipped the feature.", speakerID: "speaker-1")]
            )
        )
        harness.settingsStore.settingsValue = ValidatedMeetingSummarySettings(
            baseURL: "https://example.com",
            authToken: "secret-token",
            authHeaderName: "Authorization",
            modelName: "gpt-4o-mini",
            promptTemplate: "Summarize this transcript from {date}:\n\n{text}"
        )
        harness.transport.response = .success(
            .init(
                statusCode: 200,
                body: #"{"choices":[{"message":{"content":"  Short summary.  "}}]}"#.data(using: .utf8)!
            )
        )

        let summary = try await harness.service.summarize(meetingID: meeting.id)

        #expect(summary == "Short summary.")
        let request = try #require(harness.transport.lastRequest)
        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-4o-mini")
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.first?["role"] == "user")
        #expect(messages.first?["content"]?.contains("2024-05-10") == true)
        #expect(messages.first?["content"]?.contains("## Alice") == true)
        #expect(messages.first?["content"]?.contains("We shipped the feature.") == true)
        #expect(messages.first?["content"]?.contains("# Weekly Sync") == false)
    }

    @Test
    func summarizeUsesCustomAuthHeaderNameWithExactTokenValue() async throws {
        let harness = try MeetingSummaryServiceHarness()
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Alice")],
                segments: [TranscriptSegment(text: "We shipped the feature.", speakerID: "speaker-1")]
            )
        )
        harness.settingsStore.settingsValue = ValidatedMeetingSummarySettings(
            baseURL: "https://example.com",
            authToken: "secret-token",
            authHeaderName: "x-auth-header",
            modelName: "gpt-4o-mini",
            promptTemplate: "Summarize this transcript from {date}:\n\n{text}"
        )
        harness.transport.response = .success(
            .init(
                statusCode: 200,
                body: #"{"choices":[{"message":{"content":"Short summary."}}]}"#.data(using: .utf8)!
            )
        )

        _ = try await harness.service.summarize(meetingID: meeting.id)

        let request = try #require(harness.transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "x-auth-header") == "secret-token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func summarizeFailsWhenTranscriptIsMissing() async throws {
        let harness = try MeetingSummaryServiceHarness()
        let meeting = try harness.createRecordedMeeting()

        await #expect(throws: MeetingSummaryServiceError.transcriptMissing) {
            try await harness.service.summarize(meetingID: meeting.id)
        }
    }

    @Test
    func summarizeFailsWhenSettingsAreIncomplete() async throws {
        let harness = try MeetingSummaryServiceHarness()
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Alice")],
                segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
            )
        )
        harness.settingsStore.settingsValue = nil

        await #expect(throws: MeetingSummaryServiceError.settingsIncomplete) {
            try await harness.service.summarize(meetingID: meeting.id)
        }
    }

    @Test
    func summarizeFailsWhenAPIResponseIsInvalid() async throws {
        let harness = try MeetingSummaryServiceHarness()
        let meeting = try harness.createMeetingWithTranscript(
            StoredTranscript(
                speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Alice")],
                segments: [TranscriptSegment(text: "Hello", speakerID: "speaker-1")]
            )
        )
        harness.settingsStore.settingsValue = ValidatedMeetingSummarySettings(
            baseURL: "https://example.com/v1",
            authToken: "secret-token",
            authHeaderName: "Authorization",
            modelName: "gpt-4o-mini",
            promptTemplate: "Summarize {text} on {date}"
        )
        harness.transport.response = .success(
            .init(
                statusCode: 200,
                body: #"{"choices":[]}"#.data(using: .utf8)!
            )
        )

        await #expect(throws: MeetingSummaryServiceError.responseInvalid) {
            try await harness.service.summarize(meetingID: meeting.id)
        }
    }

    @Test
    func correctionUsesCorrectionModelPromptAndReplacesSegmentTextByID() async throws {
        let harness = try MeetingSummaryServiceHarness()
        let segmentID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let transcript = StoredTranscript(
            speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
            segments: [
                TranscriptSegment(
                    id: segmentID,
                    text: "We ship cuber net ease today.",
                    speakerID: "speaker-1"
                )
            ]
        )
        harness.settingsStore.correctionSettingsValue = ValidatedLLMCorrectionSettings(
            baseURL: "https://example.com",
            authToken: "secret-token",
            authHeaderName: "Authorization",
            modelName: "gpt-4.1-mini",
            promptTemplate: "Correct {text}\nGlossary:\n{glossary}"
        )
        harness.transport.response = .success(
            .init(
                statusCode: 200,
                body: """
                {"choices":[{"message":{"content":"{\\"segments\\":[{\\"id\\":\\"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa\\",\\"text\\":\\"We ship Kubernetes today.\\"}]}"}}]}
                """.data(using: .utf8)!
            )
        )
        let service = LLMTranscriptCorrectionService(
            settingsStore: harness.settingsStore,
            transport: harness.transport
        )

        let result = try await service.correct(
            transcript: transcript,
            glossaryTerms: [TranscriptionGlossaryTerm(text: "Kubernetes")]
        )

        #expect(result.modelName == "gpt-4.1-mini")
        #expect(result.transcript.segments.map(\.text) == ["We ship Kubernetes today."])
        #expect(result.transcript.segments.map(\.id) == [segmentID])
        let request = try #require(harness.transport.lastRequest)
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-4.1-mini")
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.first?["content"]?.contains("Kubernetes") == true)
        #expect(messages.first?["content"]?.contains(segmentID.uuidString) == true)
    }
}

nonisolated private final class StubMeetingSummarySettingsStore: MeetingSummarySettingsStoring, @unchecked Sendable {
    var settingsValue: ValidatedMeetingSummarySettings?
    var correctionSettingsValue: ValidatedLLMCorrectionSettings?

    func settings() -> MeetingSummarySettings {
        .init(
            baseURL: nil,
            authToken: nil,
            authHeaderName: nil,
            modelName: nil,
            promptTemplate: nil,
            correctionModelName: nil,
            correctionPromptTemplate: nil
        )
    }

    func validatedSettings() -> ValidatedMeetingSummarySettings? {
        settingsValue
    }

    func validatedCorrectionSettings() -> ValidatedLLMCorrectionSettings? {
        correctionSettingsValue
    }

    func saveSettings(_: MeetingSummarySettings) {}
}

nonisolated private final class StubMeetingSummaryTransport: MeetingSummaryTransporting, @unchecked Sendable {
    struct Response {
        let statusCode: Int
        let body: Data
    }

    var lastRequest: URLRequest?
    var response: Result<Response, Error> = .failure(URLError(.badServerResponse))

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request

        switch response {
        case .success(let response):
            let url = try #require(request.url)
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response.body, httpResponse)
        case .failure(let error):
            throw error
        }
    }
}

private struct MeetingSummaryServiceHarness {
    let container: ModelContainer
    let meetingStore: MeetingStore
    let settingsStore: StubMeetingSummarySettingsStore
    let transport: StubMeetingSummaryTransport
    let service: MeetingSummaryService

    init() throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        meetingStore = MeetingStore(modelContext: ModelContext(container))
        settingsStore = StubMeetingSummarySettingsStore()
        transport = StubMeetingSummaryTransport()
        service = MeetingSummaryService(
            meetingStore: meetingStore,
            settingsStore: settingsStore,
            transport: transport
        )
    }

    func createRecordedMeeting() throws -> Meeting {
        let startedAt = Date(timeIntervalSince1970: 1_715_324_400)
        let endedAt = startedAt.addingTimeInterval(60)
        let folderURL = URL(fileURLWithPath: "/tmp/meeting-\(UUID().uuidString)")
        let audioFileURL = folderURL.appendingPathComponent("audio.wav")
        let meeting = try meetingStore.createMeeting(
            title: "Weekly Sync",
            startedAt: startedAt,
            folderURL: folderURL,
            audioFileURL: audioFileURL
        )
        try meetingStore.finishRecording(meetingID: meeting.id, endedAt: endedAt)
        return try meetingStore.fetchMeeting(id: meeting.id)
    }

    func createMeetingWithTranscript(_ transcript: StoredTranscript) throws -> Meeting {
        let meeting = try createRecordedMeeting()
        try meetingStore.completeTranscription(
            meetingID: meeting.id,
            transcript: transcript,
            transcriptPreview: transcript.fullText,
            updatedAt: Date(timeIntervalSince1970: 1_715_324_800)
        )
        return try meetingStore.fetchMeeting(id: meeting.id)
    }
}
