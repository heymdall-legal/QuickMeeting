**Goal:** Make the Python sidecar launcher non-blocking so stdout progress events reach SwiftUI while transcription is still running.

**Architecture:** Keep `SidecarTranscriptionService` and the Python JSON event contract unchanged. Replace `DefaultSidecarProcessLauncher`'s synchronous `waitUntilExit()` path with an async termination continuation, stream stdout into `onLine` as lines arrive, and drain stderr concurrently so the child process cannot block on a full stderr pipe.

**Tech Stack:** Swift, Foundation `Process`/`Pipe`/`FileHandle.AsyncBytes`, Swift Testing, `xcodebuild` with `xcsift`

---

## File Map

- Modify: `QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift`
  Purpose: Launch the sidecar, stream stdout and stderr concurrently, and await process termination without blocking the main actor.
- Test: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`
  Purpose: Add focused coverage for progressive stdout delivery and stderr draining in the real launcher.

## Task 1: Prove the real launcher streams stdout before process exit

**Files:**
- Modify: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`

- [ ] **Step 1: Add the failing streaming test**

Add this test near `defaultLauncherThrowsExecutableMissingForAbsentBinary`:

```swift
@Test
func defaultLauncherDeliversStdoutLinesBeforeProcessExits() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let scriptURL = rootURL.appendingPathComponent("streaming-sidecar.sh")
    try """
    #!/bin/sh
    printf '%s\\n' '{"status":"running"}'
    sleep 1
    printf '%s\\n' '{"status":"completed","speakers":[],"segments":[]}'
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let launcher = DefaultSidecarProcessLauncher()
    let firstLine = AsyncStream<String>.makeStream()
    var deliveredLines = [String]()

    let runTask = Task {
        try await launcher.run(
            SidecarLaunchRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                workingDirectoryURL: rootURL,
                arguments: [scriptURL.path],
                environment: [:]
            )
        ) { line in
            deliveredLines.append(line)
            if deliveredLines.count == 1 {
                firstLine.continuation.yield(line)
                firstLine.continuation.finish()
            }
        }
    }

    var iterator = firstLine.stream.makeAsyncIterator()
    let observedFirstLine = await iterator.next()

    #expect(observedFirstLine == #"{"status":"running"}"#)
    #expect(!runTask.isCancelled)

    try await runTask.value
    #expect(deliveredLines == [
        #"{"status":"running"}"#,
        #"{"status":"completed","speakers":[],"segments":[]}"#,
    ])
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
rtk xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-async-sidecar CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests/defaultLauncherDeliversStdoutLinesBeforeProcessExits 2>&1 | xcsift -f toon
```

Expected: FAIL or timeout because the current launcher calls `process.waitUntilExit()` before returning control to the cooperative executor cleanly.

## Task 2: Make `DefaultSidecarProcessLauncher` fully async

**Files:**
- Modify: `QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift`

- [ ] **Step 1: Replace blocking waiting with async termination handling**

Replace the launcher body with this shape:

```swift
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
        process.environment = request.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task {
            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                try await onLine(String(line))
            }
        }
        let stderrTask = Task {
            var lines = [String]()
            for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                lines.append(String(line))
            }
            return lines.joined(separator: "\n")
        }

        let terminationStatus: Int32
        do {
            terminationStatus = try await runUntilTermination(process)
        } catch {
            stdoutTask.cancel()
            stderrTask.cancel()
            throw SidecarLaunchError.launchFailed(error.localizedDescription)
        }

        do {
            try await stdoutTask.value
        } catch {
            stderrTask.cancel()
            throw error
        }

        let stderr = (try? await stderrTask.value)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if terminationStatus != 0 {
            throw SidecarLaunchError.launchFailed(stderr.isEmpty ? "Sidecar process failed." : stderr)
        }
    }

    private func runUntilTermination(_ process: Process) async throws -> Int32 {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus)
                }

                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
```

- [ ] **Step 2: Run the focused streaming test again**

Run:

```bash
rtk xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-async-sidecar CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests/defaultLauncherDeliversStdoutLinesBeforeProcessExits 2>&1 | xcsift -f toon
```

Expected: PASS.

## Task 3: Prove stderr is drained while the process runs

**Files:**
- Modify: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`

- [ ] **Step 1: Add the stderr-drain regression test**

```swift
@Test
func defaultLauncherDrainsStderrWhileProcessRuns() async throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let scriptURL = rootURL.appendingPathComponent("stderr-heavy-sidecar.sh")
    try """
    #!/bin/sh
    i=0
    while [ "$i" -lt 20000 ]; do
      printf 'diagnostic line %s\\n' "$i" >&2
      i=$((i + 1))
    done
    printf '%s\\n' '{"status":"completed","speakers":[],"segments":[]}'
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    var lines = [String]()
    try await DefaultSidecarProcessLauncher().run(
        SidecarLaunchRequest(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            workingDirectoryURL: rootURL,
            arguments: [scriptURL.path],
            environment: [:]
        )
    ) { line in
        lines.append(line)
    }

    #expect(lines == [#"{"status":"completed","speakers":[],"segments":[]}"#])
}
```

- [ ] **Step 2: Run both launcher tests**

Run:

```bash
rtk xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-async-sidecar CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests/defaultLauncherDeliversStdoutLinesBeforeProcessExits -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests/defaultLauncherDrainsStderrWhileProcessRuns 2>&1 | xcsift -f toon
```

Expected: PASS.

## Task 4: Verify existing sidecar behavior still works

**Files:**
- Test only: `QuickMeetingTests/SidecarTranscriptionServiceTests.swift`

- [ ] **Step 1: Run the complete sidecar test suite**

Run:

```bash
rtk xcodebuild test -quiet -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-async-sidecar CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/SidecarTranscriptionServiceTests 2>&1 | xcsift -f toon
```

Expected: PASS with no regressions in transcript persistence, failure mapping, active-job guarding, launch request construction, bundle path resolution, or executable-missing behavior.

- [ ] **Step 2: Commit the implementation**

```bash
git add QuickMeeting/Services/Transcription/DefaultSidecarProcessLauncher.swift QuickMeetingTests/SidecarTranscriptionServiceTests.swift
git commit -m "fix: stream sidecar output asynchronously"
```

