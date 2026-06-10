**Goal:** Update the existing sidecar transcription integration to bundle and launch the repo-local `python/` project with its bundled `.venv` instead of the old `dist/example` executable payload.

**Architecture:** Keep the current sidecar decoder, service orchestration, and progress handling in place. Only adjust the launch request shape, default bundle-path resolution, process working directory, Xcode resource payload, and focused tests so the app runs `.venv/bin/python main.py` from the bundled `python/` tree.

**Tech Stack:** Swift, Foundation `Process`, Swift Testing, Xcode project resources, `xcodebuild`

---

## File Map

### Modify

- `QuickMeeting/Services/Transcription/SidecarProcessLaunching.swift`
  Purpose: Extend the launch request with an explicit working-directory URL for the bundled Python tree.
- `QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift`
  Purpose: Launch the bundled interpreter from `.venv/bin/python` with the `python/` folder as the working directory.
- `QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift`
  Purpose: Resolve the bundled Python interpreter path, pass `main.py` in arguments, and remove the old `example` assumptions.
- `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`
  Purpose: Update expectations for the Python interpreter path, working directory, and launch arguments.
- `QuickMeeting.xcodeproj/project.pbxproj`
  Purpose: Stop bundling `dist/example` and instead bundle the full `python/` directory.

## Task 1: Change the launch request to carry the Python working directory

**Files:**
- Modify: `QuickMeeting/Services/Transcription/SidecarProcessLaunching.swift`
- Modify: `QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift`
- Test: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing launcher-request test**

```swift
@Test
func transcribePassesPythonInterpreterWorkingDirectoryAndScriptArguments() async throws {
    let harness = try SidecarTranscriptionHarness()
    let meeting = try harness.createRecordedMeeting()
    let executableURL = URL(fileURLWithPath: "/tmp/QuickMeetingSidecar/python/.venv/bin/python")
    let workingDirectoryURL = URL(fileURLWithPath: "/tmp/QuickMeetingSidecar/python", isDirectory: true)
    let hfHomeURL = URL(fileURLWithPath: "/tmp/Application Support/QuickMeeting/HuggingFace")
    harness.runtimeConfiguration.executableURL = executableURL
    harness.runtimeConfiguration.workingDirectoryURL = workingDirectoryURL
    harness.runtimeConfiguration.hfHomeURL = hfHomeURL
    await harness.launcher.setResult(.success([
        #"{"status":"completed","speakers":[],"segments":[]}"#,
    ]))

    try await harness.service.transcribe(meetingID: meeting.id)

    let request = try await #require(harness.launcher.requests.first)
    #expect(request.executableURL == executableURL)
    #expect(request.workingDirectoryURL == workingDirectoryURL)
    #expect(request.arguments == ["main.py", "--input-file", meeting.audioFilePath, "--hf-token", "hardcoded-token"])
    #expect(request.environment["HF_HOME"] == hfHomeURL.path)
}
```

- [ ] **Step 2: Run the focused sidecar tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-python-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: FAIL because `SidecarLaunchRequest` does not yet contain `workingDirectoryURL`, and the service still builds the old executable-style argument list.

- [ ] **Step 3: Add the working-directory field and use it in the real launcher**

```swift
// QuickMeeting/Services/Transcription/SidecarProcessLaunching.swift
import Foundation

struct SidecarLaunchRequest: Sendable, Equatable {
    let executableURL: URL
    let workingDirectoryURL: URL
    let arguments: [String]
    let environment: [String: String]
}
```

```swift
// QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift
import Foundation

struct DefaultSidecarProcessLauncher: SidecarProcessLaunching {
    func run(
        _ request: SidecarLaunchRequest,
        onLine: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        guard FileManager.default.fileExists(atPath: request.executableURL.path) else {
            throw SidecarLaunchError.executableMissing
        }

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectoryURL
        process.environment = ProcessInfo.processInfo.environment.merging(request.environment) { _, new in
            new
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task {
            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                try await onLine(String(line))
            }
        }

        do {
            try process.run()
        } catch {
            stdoutTask.cancel()
            throw SidecarLaunchError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        try await stdoutTask.value

        if process.terminationStatus != 0 {
            let stderrData = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
            let stderr = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw SidecarLaunchError.launchFailed(stderr.isEmpty ? "Sidecar process failed." : stderr)
        }
    }
}
```

- [ ] **Step 4: Run the focused sidecar tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-python-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: still FAIL, but now only because `SidecarTranscriptionService` has not been updated to produce the Python-style request yet.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/SidecarProcessLaunching.swift QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift QuickMeetingTests/SidecarTranscriptionServiceTests.swift
git commit -m "refactor: support sidecar working directory"
```

## Task 2: Point the service at the bundled `python/.venv` runtime

**Files:**
- Modify: `QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift`
- Test: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`

- [ ] **Step 1: Write the failing bundle-path test**

```swift
@Test
func defaultExecutableURLResolvesBundledPythonInterpreter() {
    let bundleURL = URL(fileURLWithPath: "/tmp/QuickMeeting.app/Contents/Resources", isDirectory: true)
    let bundle = Bundle(url: bundleURL)

    let resolvedURL = SidecarTranscriptionService.defaultExecutableURL(bundle: bundle!)

    #expect(
        resolvedURL == bundleURL
            .appendingPathComponent("python", isDirectory: true)
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python", isDirectory: false)
    )
}
```

- [ ] **Step 2: Run the focused sidecar tests to verify they fail**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-python-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: FAIL because the service still resolves `Resources/example/example` and still passes the old executable-style arguments.

- [ ] **Step 3: Update the service to launch `.venv/bin/python main.py`**

```swift
// QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift
try await launcher.run(
    SidecarLaunchRequest(
        executableURL: executableURL,
        workingDirectoryURL: executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent(),
        arguments: [
            "main.py",
            "--input-file",
            audioFileURL.path,
            "--hf-token",
            hfTokenProvider(),
        ],
        environment: [
            "HF_HOME": hfHomeURLProvider().path,
        ]
    )
) { [self] line in
    try await consume(line: line, meetingID: meetingID, runState: runState)
}
```

```swift
// QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift
nonisolated static func defaultExecutableURL(bundle: Bundle = .main) -> URL? {
    bundle.resourceURL?
        .appendingPathComponent("python", isDirectory: true)
        .appendingPathComponent(".venv", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("python", isDirectory: false)
}
```

Also remove the temporary debug `print(...)` calls and the current `.replacing("m4a", with: "wav")` workaround so the service again forwards the meeting’s actual `audioFilePath`.

- [ ] **Step 4: Run the focused sidecar tests again**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-python-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift QuickMeetingTests/SidecarTranscriptionServiceTests.swift
git commit -m "feat: launch bundled python sidecar"
```

## Task 3: Replace the Xcode resource payload from `dist/example` to `python/`

**Files:**
- Modify: `QuickMeeting.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing bundle-layout verification command**

Run:

```bash
xcodebuild -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-python-sidecar-build "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY="
```

Expected: `BUILD SUCCEEDED`, but the app bundle still contains `Resources/example/...` rather than the new `Resources/python/...` payload.

- [ ] **Step 2: Switch the copied resource folder in the project file**

```pbxproj
/* Replace the existing `dist/example` folder reference with the repo-local `python` folder reference so the app bundle contains:
   QuickMeeting.app/Contents/Resources/python/main.py
   QuickMeeting.app/Contents/Resources/python/.venv/bin/python
   QuickMeeting.app/Contents/Resources/python/... */
```

- [ ] **Step 3: Rebuild and verify the new bundle layout**

Run:

```bash
xcodebuild -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-python-sidecar-build "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY="
```

Expected: `BUILD SUCCEEDED`.

Run:

```bash
find .derived-data-python-sidecar-build/Build/Products/Debug/QuickMeeting.app/Contents/Resources/python -maxdepth 3 | sed -n '1,40p'
```

Expected: output includes `main.py` and `.venv/bin/python`.

Run:

```bash
stat -f "%Sp %N" .derived-data-python-sidecar-build/Build/Products/Debug/QuickMeeting.app/Contents/Resources/python/.venv/bin/python
```

Expected: mode begins with `-rwx`, confirming the bundled interpreter kept execute permissions.

- [ ] **Step 4: Commit**

```bash
git add QuickMeeting.xcodeproj/project.pbxproj
git commit -m "build: bundle python sidecar payload"
```

## Task 4: Run final focused verification

**Files:**
- Test: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`
- Test: `QuickMeetingTests/TranscriptionServiceTests.swift`

- [ ] **Step 1: Run the focused regression suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-python-sidecar "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests -only-testing:QuickMeetingTests/TranscriptionServiceTests
```

Expected: PASS, proving the Python-sidecar adjustments work and the legacy native implementation still compiles and passes its tests.

- [ ] **Step 2: Commit only if verification forces a final fix**

```bash
git add QuickMeeting/Services/Transcription/SidecarProcessLaunching.swift QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift QuickMeeting/Services/Transcription/SidecarTranscriptionService.swift QuickMeetingTests/SidecarTranscriptionServiceTests.swift QuickMeeting.xcodeproj/project.pbxproj
git commit -m "fix: finalize python sidecar integration"
```

Only do this step if Step 1 required an additional code fix after the earlier commits.

## Self-Review

- Spec coverage:
  Task 1 covers the only new launcher shape change: explicit working directory for the bundled Python project.
  Task 2 covers Python interpreter resolution, `main.py` arguments, and removal of stale executable-mode behavior.
  Task 3 covers the only build-system change still needed: swapping the bundled payload from `dist/example` to `python/`.
  Task 4 covers final focused verification without replaying the full original rollout.
- Placeholder scan:
  The only intentionally schematic section is the `project.pbxproj` note because the exact PBX object IDs must be edited against the current project file.
- Type consistency:
  `SidecarLaunchRequest.workingDirectoryURL`, `SidecarTranscriptionService.defaultExecutableURL`, and the Python-style argument list are referenced consistently throughout the plan.
