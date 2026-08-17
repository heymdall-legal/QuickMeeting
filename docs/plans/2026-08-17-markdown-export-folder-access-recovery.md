**Goal:** Recover cleanly when macOS no longer grants QuickMeeting access to the configured Markdown export folder.

**Architecture:** `ConfiguredMeetingMarkdownExporter` will treat failure to start a security-scoped resource as a domain error, before creating or writing any export file. The existing settings view model will receive that error during folder selection, clear the unusable setting, and use the existing alert to direct the user to choose the folder again.

**Tech Stack:** Swift, Foundation security-scoped URLs, Swift Testing, SwiftData test harness.

---

## File structure

- Modify `QuickMeeting/Services/MarkdownExport/MeetingMarkdownExporter.swift`: model unavailable scoped access explicitly and inject access lifetime operations for deterministic tests.
- Modify `QuickMeetingTests/MeetingMarkdownExporterTests.swift`: prove no export write occurs when scoped access cannot be opened.
- Modify `QuickMeetingTests/MarkdownExportSettingsViewModelTests.swift`: prove failed selection clears the saved folder and supplies a recovery message.

### Task 1: Reject unavailable security-scoped export folders

**Files:**
- Modify: `QuickMeetingTests/MeetingMarkdownExporterTests.swift`
- Modify: `QuickMeeting/Services/MarkdownExport/MeetingMarkdownExporter.swift`

- [ ] **Step 1: Write the failing test**

Add this test to `MeetingMarkdownExporterTests`:

```swift
@Test
func configuredExporterRejectsDirectoryWhenScopedAccessCannotStart() throws {
    let rootURL = try temporaryExportDirectory()
    let settingsStore = InMemoryMarkdownExportSettingsStore(directoryURL: rootURL)
    let exporter = ConfiguredMeetingMarkdownExporter(
        settingsStore: settingsStore,
        startAccessingSecurityScopedResource: { _ in false },
        stopAccessingSecurityScopedResource: { _ in Issue.record("Must not stop access that did not start") }
    )

    #expect(throws: MeetingMarkdownExporterError.exportDirectoryAccessUnavailable) {
        try exporter.exportSummary(for: makeMeeting(id: UUID(), title: "Unavailable Folder", summaryText: "Summary"), summary: "Summary")
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: rootURL.path).isEmpty)
}
```

Add the local test double used above:

```swift
private struct InMemoryMarkdownExportSettingsStore: MeetingMarkdownExportSettingsStoring {
    let directoryURL: URL?

    func directoryPath() -> String? { directoryURL?.path }
    func saveDirectoryPath(_: String?) {}
    func directoryBookmarkData() -> Data? { nil }
    func saveDirectoryURL(_: URL) throws {}
    func resolvedDirectoryURL() throws -> URL? { directoryURL }
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
rtk xcsift xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-markdown-access CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:QuickMeetingTests/MeetingMarkdownExporterTests
```

Expected: the test fails to compile because the initializer labels and `exportDirectoryAccessUnavailable` do not exist.

- [ ] **Step 3: Add the minimal exporter implementation**

In `MeetingMarkdownExporterError`, add the error case and recovery text:

```swift
case exportDirectoryAccessUnavailable

case .exportDirectoryAccessUnavailable:
    return "QuickMeeting no longer has access to the Markdown export folder. Choose the folder again in Settings."
```

Extend `ConfiguredMeetingMarkdownExporter` with injected operations and defaults:

```swift
private let startAccessingSecurityScopedResource: (URL) -> Bool
private let stopAccessingSecurityScopedResource: (URL) -> Void

init(
    settingsStore: any MeetingMarkdownExportSettingsStoring,
    fileManager: FileManager = .default,
    dateProvider: @escaping () -> Date = Date.init,
    startAccessingSecurityScopedResource: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
    stopAccessingSecurityScopedResource: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
) {
    self.settingsStore = settingsStore
    self.fileManager = fileManager
    self.dateProvider = dateProvider
    self.startAccessingSecurityScopedResource = startAccessingSecurityScopedResource
    self.stopAccessingSecurityScopedResource = stopAccessingSecurityScopedResource
}
```

In `withExporter`, require access before constructing `MeetingMarkdownExporter`:

```swift
guard startAccessingSecurityScopedResource(directoryURL) else {
    throw MeetingMarkdownExporterError.exportDirectoryAccessUnavailable
}
defer { stopAccessingSecurityScopedResource(directoryURL) }
```

- [ ] **Step 4: Run the focused exporter suite**

Run:

```bash
rtk xcsift xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-markdown-access CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:QuickMeetingTests/MeetingMarkdownExporterTests
```

Expected: `configuredExporterRejectsDirectoryWhenScopedAccessCannotStart` passes, and existing Markdown exporter tests remain green.

- [ ] **Step 5: Commit the exporter change**

```bash
git add QuickMeeting/Services/MarkdownExport/MeetingMarkdownExporter.swift QuickMeetingTests/MeetingMarkdownExporterTests.swift
git commit -m "fix: recover from unavailable markdown export folder"
```

### Task 2: Clear a newly selected folder that cannot be exported to

**Files:**
- Modify: `QuickMeetingTests/MarkdownExportSettingsViewModelTests.swift`

- [ ] **Step 1: Write the failing view-model test**

Add a spy exporter and test:

```swift
@Test
func selectingDirectoryClearsSettingAndRequestsReselectionWhenBackfillCannotAccessFolder() throws {
    let settingsStore = RecordingMarkdownExportSettingsStore()
    let harness = try Harness(markdownExporter: FailingMarkdownExporter())
    _ = try harness.createCompletedMeeting()
    let viewModel = MarkdownExportSettingsViewModel(settingsStore: settingsStore, meetingStore: harness.store)
    let exportURL = try temporaryExportDirectory()

    viewModel.selectDirectory(exportURL)

    #expect(viewModel.directoryPath.isEmpty)
    #expect(settingsStore.directoryPath() == nil)
    #expect(viewModel.errorMessage == MeetingMarkdownExporterError.exportDirectoryAccessUnavailable.errorDescription)
}

private final class FailingMarkdownExporter: MeetingMarkdownExporting {
    func exportTranscript(for: Meeting, transcript: StoredTranscript) throws -> URL { throw MeetingMarkdownExporterError.exportDirectoryAccessUnavailable }
    func exportSummary(for: Meeting, summary: String) throws -> URL { throw MeetingMarkdownExporterError.exportDirectoryAccessUnavailable }
    func removeTranscript(for: UUID) throws { throw MeetingMarkdownExporterError.exportDirectoryAccessUnavailable }
    func removeSummary(for: UUID) throws { throw MeetingMarkdownExporterError.exportDirectoryAccessUnavailable }
}

private final class RecordingMarkdownExportSettingsStore: MeetingMarkdownExportSettingsStoring {
    private var storedURL: URL?

    func directoryPath() -> String? { storedURL?.path }
    func saveDirectoryPath(_ path: String?) {
        storedURL = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    func directoryBookmarkData() -> Data? { nil }
    func saveDirectoryURL(_ url: URL) throws { storedURL = url.standardizedFileURL }
    func resolvedDirectoryURL() throws -> URL? { storedURL }
}
```

The completed meeting makes `exportMarkdownForExistingMeetings()` call the failing exporter; the recording store proves that the persisted selection, not just the visible path, is cleared.

- [ ] **Step 2: Run the focused view-model suite to verify the intended failure**

Run:

```bash
rtk xcsift swift test
```

Expected: the test initially fails unless its settings-store double has been wired to reflect `saveDirectoryPath(nil)`; after that correction it passes using the existing `selectDirectory` catch path.

- [ ] **Step 3: Keep the view-model recovery path explicit**

If the test reveals only an assertion gap, make no production change: `selectDirectory` already calls `settingsStore.saveDirectoryPath(nil)`, clears `directoryPath`, and assigns the thrown error description. If required by the test-double contract, implement the state mutation only in the test double.

- [ ] **Step 4: Run the focused view-model suite**

Run:

```bash
rtk xcsift xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-markdown-access CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:QuickMeetingTests/MarkdownExportSettingsViewModelTests
```

Expected: both successful export backfill and unavailable-folder recovery tests pass.

- [ ] **Step 5: Commit the regression coverage**

```bash
git add QuickMeetingTests/MarkdownExportSettingsViewModelTests.swift
git commit -m "test: cover markdown export folder reselection"
```

### Task 3: Verify the integrated regression path

**Files:**
- Verify: `QuickMeeting/Services/MarkdownExport/MeetingMarkdownExporter.swift`
- Verify: `QuickMeetingTests/MeetingMarkdownExporterTests.swift`
- Verify: `QuickMeetingTests/MarkdownExportSettingsViewModelTests.swift`

- [ ] **Step 1: Run the narrowed final test target**

Run:

```bash
rtk xcsift xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-markdown-access CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:QuickMeetingTests/MeetingMarkdownExporterTests -only-testing:QuickMeetingTests/MarkdownExportSettingsViewModelTests
```

Expected: `TEST SUCCEEDED`, with no failures in the two Markdown export suites.

- [ ] **Step 2: Inspect the final diff**

Run:

```bash
git diff HEAD~2..HEAD --check
git status --short
```

Expected: no whitespace errors and no uncommitted implementation files.
