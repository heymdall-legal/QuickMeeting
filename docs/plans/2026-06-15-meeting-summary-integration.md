**Goal:** Wire meeting summary settings and summary generation UI to the existing LLM service, persist summaries on meetings, and require confirmation before replacing an existing summary.

**Architecture:** Keep generation, persistence, and UI state separate. `MeetingSummaryService` continues generating text, `MeetingStore` persists summaries on `Meeting`, a new summary settings view model binds the Settings sheet to `MeetingSummarySettingsStore`, and `AppViewModel` coordinates generation, replacement confirmation, and user-facing state consumed by the detail view.

**Tech Stack:** Swift, SwiftUI, SwiftData, Foundation, Testing, xcodebuild

---

### File Map

**Create:**
- `QuickMeeting/ViewModels/MeetingSummarySettingsViewModel.swift` — bindable persisted settings state for the Settings sheet
- `QuickMeetingTests/MeetingSummarySettingsViewModelTests.swift` — focused settings view-model tests

**Modify:**
- `QuickMeeting/Models/Meeting.swift` — persist summary text and clear it when transcript content is replaced
- `QuickMeeting/Services/MeetingStore.swift` — add summary save/replace helpers
- `QuickMeeting/Services/Summary/MeetingSummaryService.swift` — keep generation-only contract intact while fitting persistence flow
- `QuickMeeting/ViewModels/AppViewModel.swift` — own summary generation, confirmation, and error state
- `QuickMeeting/Views/Settings/QMSettingsSheet.swift` — replace local summary `@State` with real bindings
- `QuickMeeting/Views/MeetingSummaryPane.swift` — present stored summary plus an action label appropriate for regenerate flow
- `QuickMeeting/Views/MeetingDetailView.swift` — surface summary state, generate/regenerate action, and confirmation alert
- `QuickMeeting/QuickMeetingApp.swift` — instantiate and inject the new settings view model
- `QuickMeetingTests/MeetingStoreTests.swift` — add persistence coverage for summary save/replace and transcript reset behavior
- `QuickMeetingTests/AppViewModelTests.swift` — add generation and confirmation flow tests
- `QuickMeetingTests/MeetingSummaryServiceTests.swift` — adjust harness/schema expectations if needed

### Task 1: Persist Summary On Meeting

**Files:**
- Modify: `QuickMeetingTests/MeetingStoreTests.swift`
- Modify: `QuickMeeting/Models/Meeting.swift`
- Modify: `QuickMeeting/Services/MeetingStore.swift`

- [ ] **Step 1: Write the failing persistence tests**

```swift
@Test
func saveSummaryPersistsTextAndUpdatesMeetingTimestamp() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.createRecordedMeeting()
    let previousUpdatedAt = meeting.updatedAt

    try harness.store.saveSummary(
        meetingID: meeting.id,
        summary: "Short recap",
        updatedAt: Date(timeIntervalSince1970: 1_715_325_000)
    )

    let reloaded = try harness.store.fetchMeeting(id: meeting.id)
    #expect(reloaded.summaryText == "Short recap")
    #expect(reloaded.updatedAt > previousUpdatedAt)
}

@Test
func saveSummaryReplacesExistingText() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.createRecordedMeeting()
    try harness.store.saveSummary(
        meetingID: meeting.id,
        summary: "Old summary",
        updatedAt: Date(timeIntervalSince1970: 1_715_325_000)
    )

    try harness.store.saveSummary(
        meetingID: meeting.id,
        summary: "New summary",
        updatedAt: Date(timeIntervalSince1970: 1_715_325_060)
    )

    let reloaded = try harness.store.fetchMeeting(id: meeting.id)
    #expect(reloaded.summaryText == "New summary")
}

@Test
func startingOrCompletingTranscriptionClearsStoredSummary() throws {
    let harness = try MeetingStoreHarness()
    let meeting = try harness.createRecordedMeeting()
    let transcript = StoredTranscript(
        speakers: [TranscriptSpeaker(id: "speaker-1", displayName: "Alice")],
        segments: [TranscriptSegment(text: "First pass", speakerID: "speaker-1")]
    )
    try harness.store.saveSummary(
        meetingID: meeting.id,
        summary: "Old summary",
        updatedAt: Date(timeIntervalSince1970: 1_715_325_000)
    )

    try harness.store.startTranscription(
        meetingID: meeting.id,
        updatedAt: Date(timeIntervalSince1970: 1_715_325_060)
    )
    #expect(try harness.store.fetchMeeting(id: meeting.id).summaryText == nil)

    try harness.store.completeTranscription(
        meetingID: meeting.id,
        transcript: transcript,
        transcriptPreview: transcript.fullText,
        updatedAt: Date(timeIntervalSince1970: 1_715_325_120)
    )
    #expect(try harness.store.fetchMeeting(id: meeting.id).summaryText == nil)
}
```

- [ ] **Step 2: Run the targeted store tests to verify they fail**

Run:
```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-summary CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests -quiet
```

Expected:
```text
error: value of type 'Meeting' has no member 'summaryText'
error: value of type 'MeetingStore' has no member 'saveSummary'
```

- [ ] **Step 3: Write the minimal persistence implementation**

```swift
@Model
final class Meeting {
    private(set) var summaryText: String?

    init(
        // existing parameters...
        summaryText: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        // existing assignments...
        self.summaryText = summaryText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func beginTranscription(updatedAt: Date = Date()) {
        transcriptPreview = nil
        transcriptSpeakers.removeAll()
        transcriptSegments.removeAll()
        summaryText = nil
        touch(updatedAt: updatedAt)
    }

    func completeTranscription(
        transcript: StoredTranscript,
        transcriptPreview: String,
        updatedAt: Date = Date()
    ) {
        self.transcriptPreview = transcriptPreview
        transcriptSpeakers = transcript.speakers.map(PersistedTranscriptSpeaker.init)
        transcriptSegments = transcript.segments.map(PersistedTranscriptSegment.init)
        summaryText = nil
        statusRawValue = MeetingStatus.completed.rawValue
        touch(updatedAt: updatedAt)
    }

    func storeSummary(_ summary: String, updatedAt: Date = Date()) {
        summaryText = summary
        touch(updatedAt: updatedAt)
    }
}

struct MeetingStore {
    func saveSummary(meetingID: UUID, summary: String, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.storeSummary(summary, updatedAt: updatedAt)
        try modelContext.save()
    }
}
```

- [ ] **Step 4: Run the targeted store tests to verify they pass**

Run:
```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-summary CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingStoreTests -quiet
```

Expected:
```text
Test Suite 'MeetingStoreTests' passed
Executed N tests, with 0 failures
BUILD SUCCEEDED
```

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Models/Meeting.swift QuickMeeting/Services/MeetingStore.swift QuickMeetingTests/MeetingStoreTests.swift
git commit -m "Persist meeting summaries"
```

### Task 2: Add Summary Settings View Model And Wire Settings Sheet

**Files:**
- Create: `QuickMeeting/ViewModels/MeetingSummarySettingsViewModel.swift`
- Create: `QuickMeetingTests/MeetingSummarySettingsViewModelTests.swift`
- Modify: `QuickMeeting/Views/Settings/QMSettingsSheet.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`

- [ ] **Step 1: Write the failing settings view-model tests**

```swift
@Test
func loadsStoredValuesIntoBindableFields() {
    let store = StubMeetingSummarySettingsStore()
    store.rawSettings = .init(
        baseURL: "https://example.com",
        authToken: "secret",
        modelName: "gpt-4o-mini",
        promptTemplate: "Summarize {text} on {date}"
    )

    let viewModel = MeetingSummarySettingsViewModel(settingsStore: store)

    #expect(viewModel.baseURL == "https://example.com")
    #expect(viewModel.authToken == "secret")
    #expect(viewModel.modelName == "gpt-4o-mini")
    #expect(viewModel.promptTemplate == "Summarize {text} on {date}")
}

@Test
func savePersistsEditedValues() {
    let store = StubMeetingSummarySettingsStore()
    let viewModel = MeetingSummarySettingsViewModel(settingsStore: store)
    viewModel.baseURL = "https://localhost:1234/v1"
    viewModel.authToken = "token"
    viewModel.modelName = "local-model"
    viewModel.promptTemplate = "Template {text}"

    viewModel.save()

    #expect(store.savedSettings == .init(
        baseURL: "https://localhost:1234/v1",
        authToken: "token",
        modelName: "local-model",
        promptTemplate: "Template {text}"
    ))
}
```

- [ ] **Step 2: Run the targeted settings view-model tests to verify they fail**

Run:
```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-summary CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingSummarySettingsViewModelTests -quiet
```

Expected:
```text
error: cannot find 'MeetingSummarySettingsViewModel' in scope
```

- [ ] **Step 3: Write the minimal settings view model and sheet wiring**

```swift
@MainActor
final class MeetingSummarySettingsViewModel: ObservableObject {
    @Published var baseURL: String
    @Published var authToken: String
    @Published var modelName: String
    @Published var promptTemplate: String

    private let settingsStore: any MeetingSummarySettingsStoring
    static let defaultPromptTemplate = """
    Summarize the following meeting transcript from {date}.

    Return:
    • A 2–3 sentence overview
    • Key decisions
    • Action items (owner — task)

    Transcript:
    {text}
    """

    init(settingsStore: any MeetingSummarySettingsStoring = MeetingSummarySettingsStore()) {
        self.settingsStore = settingsStore
        let settings = settingsStore.settings()
        baseURL = settings.baseURL ?? ""
        authToken = settings.authToken ?? ""
        modelName = settings.modelName ?? ""
        promptTemplate = settings.promptTemplate ?? Self.defaultPromptTemplate
    }

    func save() {
        settingsStore.saveSettings(.init(
            baseURL: baseURL,
            authToken: authToken,
            modelName: modelName,
            promptTemplate: promptTemplate
        ))
    }
}

struct QMSettingsSheet: View {
    @ObservedObject var meetingSummaryViewModel: MeetingSummarySettingsViewModel

    private var aiSummarizationSection: some View {
        TextField("https://api.openai.com/v1", text: $meetingSummaryViewModel.baseURL)
            .onChange(of: meetingSummaryViewModel.baseURL) { _, _ in meetingSummaryViewModel.save() }
        SecureField("Token", text: $meetingSummaryViewModel.authToken)
            .onChange(of: meetingSummaryViewModel.authToken) { _, _ in meetingSummaryViewModel.save() }
        TextField("gpt-4o-mini", text: $meetingSummaryViewModel.modelName)
            .onChange(of: meetingSummaryViewModel.modelName) { _, _ in meetingSummaryViewModel.save() }
        TextEditor(text: $meetingSummaryViewModel.promptTemplate)
            .onChange(of: meetingSummaryViewModel.promptTemplate) { _, _ in meetingSummaryViewModel.save() }
    }
}
```

- [ ] **Step 4: Run the targeted settings view-model tests to verify they pass**

Run:
```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-summary CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingSummarySettingsViewModelTests -quiet
```

Expected:
```text
Test Suite 'MeetingSummarySettingsViewModelTests' passed
Executed N tests, with 0 failures
BUILD SUCCEEDED
```

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/ViewModels/MeetingSummarySettingsViewModel.swift QuickMeeting/Views/Settings/QMSettingsSheet.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/MeetingSummarySettingsViewModelTests.swift
git commit -m "Wire summary settings UI"
```

### Task 3: Add App-Level Summary Generation Flow

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Modify: `QuickMeetingTests/MeetingSummaryServiceTests.swift`

- [ ] **Step 1: Write the failing app view-model tests**

```swift
@Test
func generateSummaryWithoutExistingSummarySavesResult() async throws {
    let harness = try AppViewModelHarness()
    let meeting = try harness.createCompletedMeeting(summaryText: nil)
    harness.summaryService.summaryResult = .success("Fresh summary")

    await harness.viewModel.generateSummary(for: meeting)

    let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
    #expect(reloaded.summaryText == "Fresh summary")
    #expect(harness.viewModel.summaryConfirmationMeetingID == nil)
    #expect(harness.viewModel.summaryErrorMessage == nil)
}

@Test
func generateSummaryWithExistingSummaryRequestsConfirmation() async throws {
    let harness = try AppViewModelHarness()
    let meeting = try harness.createCompletedMeeting(summaryText: "Existing summary")

    await harness.viewModel.generateSummary(for: meeting)

    #expect(harness.viewModel.summaryConfirmationMeetingID == meeting.id)
    #expect(harness.summaryService.invocationCount == 0)
}

@Test
func confirmSummaryReplacementOverwritesStoredSummary() async throws {
    let harness = try AppViewModelHarness()
    let meeting = try harness.createCompletedMeeting(summaryText: "Old summary")
    harness.summaryService.summaryResult = .success("New summary")

    await harness.viewModel.generateSummary(for: meeting)
    await harness.viewModel.confirmSummaryReplacement()

    let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
    #expect(reloaded.summaryText == "New summary")
    #expect(harness.viewModel.summaryConfirmationMeetingID == nil)
}

@Test
func failedReplacementPreservesExistingSummary() async throws {
    let harness = try AppViewModelHarness()
    let meeting = try harness.createCompletedMeeting(summaryText: "Old summary")
    harness.summaryService.summaryResult = .failure(MeetingSummaryServiceError.responseInvalid)

    await harness.viewModel.generateSummary(for: meeting)
    await harness.viewModel.confirmSummaryReplacement()

    let reloaded = try harness.meetingStore.fetchMeeting(id: meeting.id)
    #expect(reloaded.summaryText == "Old summary")
    #expect(harness.viewModel.summaryErrorMessage == MeetingSummaryServiceError.responseInvalid.localizedDescription)
}
```

- [ ] **Step 2: Run the targeted app view-model tests to verify they fail**

Run:
```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-summary CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests -quiet
```

Expected:
```text
error: value of type 'AppViewModel' has no member 'generateSummary'
error: value of type 'AppViewModel' has no member 'summaryConfirmationMeetingID'
```

- [ ] **Step 3: Write the minimal generation and confirmation implementation**

```swift
@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var summaryErrorMessage: String?
    @Published private(set) var summaryConfirmationMeetingID: UUID?
    @Published private(set) var summarizingMeetingID: UUID?

    private let meetingSummaryService: MeetingSummaryService
    private var pendingSummaryReplacementMeetingID: UUID?

    func generateSummary(for meeting: Meeting) async {
        summaryErrorMessage = nil

        if meeting.summaryText != nil {
            pendingSummaryReplacementMeetingID = meeting.id
            summaryConfirmationMeetingID = meeting.id
            return
        }

        await runSummaryGeneration(for: meeting.id)
    }

    func confirmSummaryReplacement() async {
        guard let meetingID = pendingSummaryReplacementMeetingID else { return }
        pendingSummaryReplacementMeetingID = nil
        summaryConfirmationMeetingID = nil
        await runSummaryGeneration(for: meetingID)
    }

    func cancelSummaryReplacement() {
        pendingSummaryReplacementMeetingID = nil
        summaryConfirmationMeetingID = nil
    }

    private func runSummaryGeneration(for meetingID: UUID) async {
        summarizingMeetingID = meetingID
        defer { summarizingMeetingID = nil }

        do {
            let summary = try await meetingSummaryService.summarize(meetingID: meetingID)
            try meetingStore.saveSummary(meetingID: meetingID, summary: summary, updatedAt: dateProvider())
        } catch {
            summaryErrorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Run the targeted app view-model tests to verify they pass**

Run:
```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-summary CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests -quiet
```

Expected:
```text
Test Suite 'AppViewModelTests' passed
Executed N tests, with 0 failures
BUILD SUCCEEDED
```

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/AppViewModelTests.swift QuickMeetingTests/MeetingSummaryServiceTests.swift
git commit -m "Add summary generation flow"
```

### Task 4: Wire Summary Detail UI To Real State

**Files:**
- Modify: `QuickMeeting/Views/MeetingSummaryPane.swift`
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeeting/ContentView.swift`

- [ ] **Step 1: Write the failing UI behavior tests**

```swift
@Test
func summaryPaneShowsStoredSummaryTextWhenPresent() {
    let view = MeetingSummaryPane(
        state: .ready("Stored summary"),
        actionTitle: "Regenerate Summary",
        onGenerate: {}
    )

    #expect(view.inspect().find(text: "Stored summary") != nil)
}

@Test
func detailViewShowsReplacementAlertWhenViewModelRequestsIt() async throws {
    let harness = try MeetingDetailViewHarness()
    let meeting = try harness.createCompletedMeeting(summaryText: "Existing summary")

    await harness.viewModel.generateSummary(for: meeting)

    #expect(harness.viewModel.summaryConfirmationMeetingID == meeting.id)
}
```

- [ ] **Step 2: Run the targeted UI tests to verify they fail**

Run:
```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-summary CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingDetailFocusManagementTests -quiet
```

Expected:
```text
error: extra argument 'actionTitle' in call
error: summary replacement alert is not present
```

- [ ] **Step 3: Write the minimal detail wiring**

```swift
struct MeetingSummaryPane: View {
    let state: SummaryPaneState
    let actionTitle: String
    let onGenerate: () -> Void

    private var readyToolbarButtonTitle: String {
        actionTitle
    }
}

struct MeetingDetailView: View {
    let onGenerateSummary: () -> Void
    let onConfirmSummaryReplacement: () -> Void
    let onCancelSummaryReplacement: () -> Void
    let isShowingSummaryReplacementConfirmation: Bool

    .alert("Replace Summary?", isPresented: summaryReplacementBinding) {
        Button("Replace", role: .destructive, action: onConfirmSummaryReplacement)
        Button("Cancel", role: .cancel, action: onCancelSummaryReplacement)
    } message: {
        Text("Generating a new summary will replace the summary currently stored for this meeting.")
    }

    private var summaryViewState: SummaryPaneState {
        if isSummarizingMeeting {
            return .generating
        }
        if let summaryErrorMessage {
            return .failed(summaryErrorMessage)
        }
        if let summary = meeting.summaryText {
            return .ready(summary)
        }
        return .idle
    }
}
```

- [ ] **Step 4: Run the targeted UI tests to verify they pass**

Run:
```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-summary CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests -only-testing:QuickMeetingTests/MeetingDetailFocusManagementTests -quiet
```

Expected:
```text
Executed N tests, with 0 failures
BUILD SUCCEEDED
```

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Views/MeetingSummaryPane.swift QuickMeeting/Views/MeetingDetailView.swift QuickMeeting/ContentView.swift
git commit -m "Wire meeting summary detail UI"
```

### Task 5: Run Focused Regression Verification

**Files:**
- Modify: `QuickMeetingTests/MeetingSummaryServiceTests.swift`
- Modify: `QuickMeetingTests/MeetingSummarySettingsStoreTests.swift`
- Modify: `QuickMeetingTests/MeetingStoreTests.swift`
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeetingTests/MeetingSummarySettingsViewModelTests.swift`

- [ ] **Step 1: Add any missing harness/schema adjustments uncovered by the earlier tasks**

```swift
let schema = Schema([
    Meeting.self,
    PersistedTranscriptSpeaker.self,
    PersistedTranscriptSegment.self,
    PersistedKnownSpeaker.self,
    PersistedKnownSpeakerCentroid.self,
])
```

- [ ] **Step 2: Run the focused summary-related suite**

Run:
```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-summary CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingSummaryServiceTests -only-testing:QuickMeetingTests/MeetingSummarySettingsStoreTests -only-testing:QuickMeetingTests/MeetingSummarySettingsViewModelTests -only-testing:QuickMeetingTests/MeetingStoreTests -only-testing:QuickMeetingTests/AppViewModelTests -quiet
```

Expected:
```text
Executed N tests, with 0 failures
BUILD SUCCEEDED
```

- [ ] **Step 3: Run one broader safety net around the touched detail behavior**

Run:
```bash
rtk xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-summary CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/MeetingDetailFocusManagementTests -only-testing:QuickMeetingTests/MeetingTranscriptContentTests -only-testing:QuickMeetingTests/MeetingTranscriptExportTests -quiet
```

Expected:
```text
Executed N tests, with 0 failures
BUILD SUCCEEDED
```

- [ ] **Step 4: Commit**

```bash
git add QuickMeetingTests/MeetingSummaryServiceTests.swift QuickMeetingTests/MeetingSummarySettingsStoreTests.swift QuickMeetingTests/MeetingSummarySettingsViewModelTests.swift QuickMeetingTests/MeetingStoreTests.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "Verify meeting summary integration"
```
