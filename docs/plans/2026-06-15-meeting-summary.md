**Goal:** Add an internal service that summarizes an existing meeting transcript through an OpenAI-compatible `chat/completions` API using persisted user settings and prompt templating.

**Architecture:** Keep summarization isolated in a new `MeetingSummaryService` that depends on `MeetingStore`, a `UserDefaults`-backed `MeetingSummarySettingsStore`, the existing transcript export formatter, and a tiny injectable HTTP transport seam. Extend transcript export with a body-only rendering helper so prompt `{text}` uses the same grouping rules as normal export without duplicating formatting logic.

**Tech Stack:** Swift, Foundation, SwiftData, Swift Testing, `xcodebuild` test runner, `xcsift`

---

### Task 1: Add the summarization settings store

**Files:**
- Create: `QuickMeeting/Services/Summary/MeetingSummarySettingsStore.swift`
- Create: `QuickMeetingTests/MeetingSummarySettingsStoreTests.swift`

- [ ] **Step 1: Write the failing settings store tests**

Create `QuickMeetingTests/MeetingSummarySettingsStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct MeetingSummarySettingsStoreTests {
    @Test
    func returnsNilValidatedSettingsWhenAnyRequiredValueIsMissing() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = MeetingSummarySettingsStore(userDefaults: defaults)

        #expect(store.settings() == MeetingSummarySettings(
            baseURL: nil,
            authToken: nil,
            modelName: nil,
            promptTemplate: nil
        ))
        #expect(store.validatedSettings() == nil)
    }

    @Test
    func persistsAndReloadsAllRawValues() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = MeetingSummarySettingsStore(userDefaults: defaults)

        store.saveSettings(.init(
            baseURL: " https://example.com ",
            authToken: " token ",
            modelName: " gpt-4o-mini ",
            promptTemplate: "Summarize {text} for {date}"
        ))

        #expect(store.settings() == MeetingSummarySettings(
            baseURL: " https://example.com ",
            authToken: " token ",
            modelName: " gpt-4o-mini ",
            promptTemplate: "Summarize {text} for {date}"
        ))
    }

    @Test
    func validatedSettingsTrimWhitespaceAndRequireAllValues() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = MeetingSummarySettingsStore(userDefaults: defaults)
        store.saveSettings(.init(
            baseURL: " https://example.com/v1 ",
            authToken: " secret-token ",
            modelName: " gpt-4o-mini ",
            promptTemplate: " Summarize {text} on {date} "
        ))

        #expect(store.validatedSettings() == ValidatedMeetingSummarySettings(
            baseURL: "https://example.com/v1",
            authToken: "secret-token",
            modelName: "gpt-4o-mini",
            promptTemplate: "Summarize {text} on {date}"
        ))
    }
}
```

- [ ] **Step 2: Run the focused settings tests and verify RED**

Run:

```bash
rtk xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination "platform=macOS" \
  -derivedDataPath .derived-data-meeting-summary \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -only-testing:QuickMeetingTests/MeetingSummarySettingsStoreTests \
  2>&1 | rtk xcsift -f toon -q
```

Expected: FAIL at compile time because `MeetingSummarySettingsStore`, `MeetingSummarySettings`, and `ValidatedMeetingSummarySettings` do not exist yet.

- [ ] **Step 3: Write the minimal settings store implementation**

Create `QuickMeeting/Services/Summary/MeetingSummarySettingsStore.swift`:

```swift
import Foundation

struct MeetingSummarySettings: Equatable {
    var baseURL: String?
    var authToken: String?
    var modelName: String?
    var promptTemplate: String?
}

struct ValidatedMeetingSummarySettings: Equatable, Sendable {
    let baseURL: String
    let authToken: String
    let modelName: String
    let promptTemplate: String
}

protocol MeetingSummarySettingsStoring: Sendable {
    func settings() -> MeetingSummarySettings
    func validatedSettings() -> ValidatedMeetingSummarySettings?
    func saveSettings(_ settings: MeetingSummarySettings)
}

struct MeetingSummarySettingsStore: MeetingSummarySettingsStoring {
    private let userDefaults: UserDefaults
    private let baseURLKey = "meetingSummary.baseURL"
    private let authTokenKey = "meetingSummary.authToken"
    private let modelNameKey = "meetingSummary.modelName"
    private let promptTemplateKey = "meetingSummary.promptTemplate"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func settings() -> MeetingSummarySettings {
        MeetingSummarySettings(
            baseURL: userDefaults.string(forKey: baseURLKey),
            authToken: userDefaults.string(forKey: authTokenKey),
            modelName: userDefaults.string(forKey: modelNameKey),
            promptTemplate: userDefaults.string(forKey: promptTemplateKey)
        )
    }

    func validatedSettings() -> ValidatedMeetingSummarySettings? {
        let current = settings()

        guard
            let baseURL = current.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            let authToken = current.authToken?.trimmingCharacters(in: .whitespacesAndNewlines),
            let modelName = current.modelName?.trimmingCharacters(in: .whitespacesAndNewlines),
            let promptTemplate = current.promptTemplate?.trimmingCharacters(in: .whitespacesAndNewlines),
            !baseURL.isEmpty,
            !authToken.isEmpty,
            !modelName.isEmpty,
            !promptTemplate.isEmpty
        else {
            return nil
        }

        return ValidatedMeetingSummarySettings(
            baseURL: baseURL,
            authToken: authToken,
            modelName: modelName,
            promptTemplate: promptTemplate
        )
    }

    func saveSettings(_ settings: MeetingSummarySettings) {
        save(settings.baseURL, forKey: baseURLKey)
        save(settings.authToken, forKey: authTokenKey)
        save(settings.modelName, forKey: modelNameKey)
        save(settings.promptTemplate, forKey: promptTemplateKey)
    }

    private func save(_ value: String?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}
```

- [ ] **Step 4: Run the focused settings tests and verify GREEN**

Run:

```bash
rtk xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination "platform=macOS" \
  -derivedDataPath .derived-data-meeting-summary \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -only-testing:QuickMeetingTests/MeetingSummarySettingsStoreTests \
  2>&1 | rtk xcsift -f toon -q
```

Expected: PASS with all `MeetingSummarySettingsStoreTests` tests green.

- [ ] **Step 5: Commit the tested settings store**

```bash
rtk git add QuickMeeting/Services/Summary/MeetingSummarySettingsStore.swift QuickMeetingTests/MeetingSummarySettingsStoreTests.swift
rtk git commit -m "Add meeting summary settings store"
```

### Task 2: Extend transcript export with summary body rendering

**Files:**
- Modify: `QuickMeeting/Support/MeetingTranscriptExport.swift`
- Modify: `QuickMeetingTests/MeetingTranscriptExportTests.swift`

- [ ] **Step 1: Write the failing transcript body rendering test**

Add to `QuickMeetingTests/MeetingTranscriptExportTests.swift`:

```swift
@Test
func exportMarkdownBodyOmitsMeetingHeadersAndKeepsGroupedSpeakerSections() {
    let meeting = Meeting(
        title: "Weekly Sync",
        startedAt: Date(timeIntervalSince1970: 1_715_324_400),
        status: .completed,
        audioFilePath: "/tmp/audio.wav",
        duration: 3_900
    )
    let transcript = StoredTranscript(
        speakers: [
            TranscriptSpeaker(id: "speaker-1", displayName: "Alice"),
            TranscriptSpeaker(id: "speaker-2", displayName: "Bob")
        ],
        segments: [
            TranscriptSegment(text: "Kickoff update.", startTime: 0, endTime: 2, speakerID: "speaker-1"),
            TranscriptSegment(text: "Next agenda point.", startTime: 2, endTime: 4, speakerID: "speaker-1"),
            TranscriptSegment(text: "Looks good to me.", startTime: 4, endTime: 6, speakerID: "speaker-2")
        ]
    )

    let markdown = renderMeetingTranscriptExportMarkdownBody(
        meeting: meeting,
        transcript: transcript
    )

    #expect(markdown == """
    ## Alice
    Kickoff update.

    Next agenda point.

    ## Bob
    Looks good to me.
    """)
}
```

- [ ] **Step 2: Run the focused export tests and verify RED**

Run:

```bash
rtk xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination "platform=macOS" \
  -derivedDataPath .derived-data-meeting-summary \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -only-testing:QuickMeetingTests/MeetingTranscriptExportTests \
  2>&1 | rtk xcsift -f toon -q
```

Expected: FAIL because `renderMeetingTranscriptExportMarkdownBody(meeting:transcript:)` does not exist.

- [ ] **Step 3: Implement the body-only export helper with shared formatting**

Update `QuickMeeting/Support/MeetingTranscriptExport.swift` so the shared speaker section formatting lives in one helper and add:

```swift
func renderMeetingTranscriptExportMarkdownBody(
    meeting _: Meeting,
    transcript: StoredTranscript
) -> String {
    transcriptExportSections(transcript).joined(separator: "\n\n")
}
```

Refactor `renderMeetingTranscriptExportMarkdown(meeting:transcript:)` to reuse the same `transcriptExportSections(_:)` helper:

```swift
private func transcriptExportSections(_ transcript: StoredTranscript) -> [String] {
    let speakerNames = Dictionary(uniqueKeysWithValues: transcript.speakers.map { ($0.id, $0.displayName) })

    return transcript.segments.reduce(into: [(speakerName: String, lines: [String])]()) { result, segment in
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
}
```

- [ ] **Step 4: Run the focused export tests and verify GREEN**

Run:

```bash
rtk xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination "platform=macOS" \
  -derivedDataPath .derived-data-meeting-summary \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -only-testing:QuickMeetingTests/MeetingTranscriptExportTests \
  2>&1 | rtk xcsift -f toon -q
```

Expected: PASS with existing header export tests and the new body-only test green.

- [ ] **Step 5: Commit the shared export formatting**

```bash
rtk git add QuickMeeting/Support/MeetingTranscriptExport.swift QuickMeetingTests/MeetingTranscriptExportTests.swift
rtk git commit -m "Add transcript export body rendering"
```

### Task 3: Add the summarization service and transport seam

**Files:**
- Create: `QuickMeeting/Services/Summary/MeetingSummaryService.swift`
- Create: `QuickMeetingTests/MeetingSummaryServiceTests.swift`
- Reuse: `QuickMeeting/Services/MeetingStore.swift`
- Reuse: `QuickMeeting/Support/MeetingTranscriptExport.swift`

- [ ] **Step 1: Write the failing summarization service tests**

Create `QuickMeetingTests/MeetingSummaryServiceTests.swift`:

```swift
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
            modelName: "gpt-4o-mini",
            promptTemplate: "Summarize this transcript from {date}:\n\n{text}"
        )
        harness.transport.response = .success(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"  Short summary.  "}}]}"#.data(using: .utf8)!
        )

        let summary = try await harness.service.summarize(meetingID: meeting.id)

        #expect(summary == "Short summary.")
        let request = try #require(harness.transport.lastRequest)
        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["model"] as? String == "gpt-4o-mini")
        let messages = try #require(json?["messages"] as? [[String: String]])
        #expect(messages.first?["role"] == "user")
        #expect(messages.first?["content"]?.contains("2024-05-10") == true)
        #expect(messages.first?["content"]?.contains("## Alice") == true)
        #expect(messages.first?["content"]?.contains("We shipped the feature.") == true)
        #expect(messages.first?["content"]?.contains("# Weekly Sync") == false)
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
            modelName: "gpt-4o-mini",
            promptTemplate: "Summarize {text} on {date}"
        )
        harness.transport.response = .success(
            statusCode: 200,
            body: #"{"choices":[]}"#.data(using: .utf8)!
        )

        await #expect(throws: MeetingSummaryServiceError.responseInvalid) {
            try await harness.service.summarize(meetingID: meeting.id)
        }
    }
}
```

Append to the same test file:

```swift
private final class StubMeetingSummarySettingsStore: MeetingSummarySettingsStoring, @unchecked Sendable {
    var settingsValue: ValidatedMeetingSummarySettings?

    func settings() -> MeetingSummarySettings { .init(baseURL: nil, authToken: nil, modelName: nil, promptTemplate: nil) }
    func validatedSettings() -> ValidatedMeetingSummarySettings? { settingsValue }
    func saveSettings(_: MeetingSummarySettings) {}
}

private final class StubMeetingSummaryTransport: MeetingSummaryTransporting, @unchecked Sendable {
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
```

- [ ] **Step 2: Run the focused service tests and verify RED**

Run:

```bash
rtk xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination "platform=macOS" \
  -derivedDataPath .derived-data-meeting-summary \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -only-testing:QuickMeetingTests/MeetingSummaryServiceTests \
  2>&1 | rtk xcsift -f toon -q
```

Expected: FAIL at compile time because the summary service and transport types do not exist yet.

- [ ] **Step 3: Implement the minimal summary service**

Create `QuickMeeting/Services/Summary/MeetingSummaryService.swift`:

```swift
import Foundation

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
            return "Summary settings are incomplete."
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

struct MeetingSummaryService {
    private let meetingStore: MeetingStore
    private let settingsStore: any MeetingSummarySettingsStoring
    private let transport: any MeetingSummaryTransporting

    init(
        meetingStore: MeetingStore,
        settingsStore: any MeetingSummarySettingsStoring = MeetingSummarySettingsStore(),
        transport: any MeetingSummaryTransporting = URLSessionMeetingSummaryTransport()
    ) {
        self.meetingStore = meetingStore
        self.settingsStore = settingsStore
        self.transport = transport
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
            let content = payload.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines),
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
        request.setValue("Bearer \(settings.authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            MeetingSummaryRequest(
                model: settings.modelName,
                messages: [.init(role: "user", content: prompt)]
            )
        )
        return request
    }
}

private struct MeetingSummaryRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
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
```

- [ ] **Step 4: Run the focused service tests and verify GREEN**

Run:

```bash
rtk xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination "platform=macOS" \
  -derivedDataPath .derived-data-meeting-summary \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -only-testing:QuickMeetingTests/MeetingSummaryServiceTests \
  2>&1 | rtk xcsift -f toon -q
```

Expected: PASS with the summary service tests green.

- [ ] **Step 5: Commit the tested summary service**

```bash
rtk git add QuickMeeting/Services/Summary/MeetingSummaryService.swift QuickMeetingTests/MeetingSummaryServiceTests.swift
rtk git commit -m "Add meeting transcript summary service"
```

### Task 4: Run focused regression coverage across the new feature

**Files:**
- Reuse: `QuickMeetingTests/MeetingSummarySettingsStoreTests.swift`
- Reuse: `QuickMeetingTests/MeetingTranscriptExportTests.swift`
- Reuse: `QuickMeetingTests/MeetingSummaryServiceTests.swift`

- [ ] **Step 1: Run the combined focused suite**

Run:

```bash
rtk xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination "platform=macOS" \
  -derivedDataPath .derived-data-meeting-summary \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  -only-testing:QuickMeetingTests/MeetingSummarySettingsStoreTests \
  -only-testing:QuickMeetingTests/MeetingTranscriptExportTests \
  -only-testing:QuickMeetingTests/MeetingSummaryServiceTests \
  2>&1 | rtk xcsift -f toon -q
```

Expected: PASS with all three targeted test suites green and no new warnings or compile errors in the touched code.

- [ ] **Step 2: Commit the fully verified feature slice**

```bash
rtk git add QuickMeeting/Services/Summary/MeetingSummarySettingsStore.swift \
  QuickMeeting/Services/Summary/MeetingSummaryService.swift \
  QuickMeeting/Support/MeetingTranscriptExport.swift \
  QuickMeetingTests/MeetingSummarySettingsStoreTests.swift \
  QuickMeetingTests/MeetingSummaryServiceTests.swift \
  QuickMeetingTests/MeetingTranscriptExportTests.swift
rtk git commit -m "Add internal meeting summary pipeline"
```
