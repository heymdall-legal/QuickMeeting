**Goal:** Reduce new meeting recording sizes by switching QuickMeeting from uncompressed `audio.wav` output to AAC-encoded `audio.m4a` at `96 kbps` without materially changing playback or transcription behavior.

**Architecture:** Keep the existing ScreenCaptureKit capture, PCM normalization, and audio mixing path intact, and isolate the format change at the file-writing boundary. New meetings will store an `audio.m4a` artifact path, and the native recording pipeline will write AAC/M4A output from the same canonical PCM buffers it already produces.

**Tech Stack:** Swift, AVFoundation, ScreenCaptureKit, SwiftData, Testing, xcodebuild

---

## File Structure

- Modify: `QuickMeeting/Services/MeetingFileStore.swift`
  Changes new meeting artifact naming from `audio.wav` to `audio.m4a`.
- Modify: `QuickMeeting/Services/Recording/AudioCapturePipeline.swift`
  Replaces the WAV-specific writer with an AAC/M4A writer configured for `96 kbps` and wires the native pipeline convenience initializer to use it.
- Modify: `QuickMeetingTests/MeetingFileStoreTests.swift`
  Updates the artifact-creation expectation for new recordings.
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
  Updates focused native pipeline coverage to use the new extension and adds a real writer integration test that proves an `m4a` file is created and readable.

### Task 1: Change new meeting artifacts to `audio.m4a`

**Files:**
- Modify: `QuickMeetingTests/MeetingFileStoreTests.swift`
- Modify: `QuickMeeting/Services/MeetingFileStore.swift`

- [ ] **Step 1: Write the failing artifact test**

Change the assertion in `QuickMeetingTests/MeetingFileStoreTests.swift`:

```swift
@Test
func createArtifactsCreatesMeetingFolderAndAudioFilePath() throws {
    let fileManager = FileManager.default
    let rootURL = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = MeetingFileStore(fileManager: fileManager, rootURL: rootURL)

    let meetingID = UUID()
    let startedAt = Date(timeIntervalSince1970: 1_234_567_890)

    let artifacts = try store.createArtifacts(for: meetingID, startedAt: startedAt)

    var isDirectory = ObjCBool(false)
    let folderExists = fileManager.fileExists(
        atPath: artifacts.meetingFolderURL.path,
        isDirectory: &isDirectory
    )

    #expect(folderExists)
    #expect(isDirectory.boolValue)
    #expect(artifacts.meetingFolderURL.lastPathComponent == meetingID.uuidString)
    #expect(
        artifacts.audioFileURL.deletingLastPathComponent().standardizedFileURL
            == artifacts.meetingFolderURL.standardizedFileURL
    )
    #expect(artifacts.audioFileURL.lastPathComponent == "audio.m4a")
}
```

- [ ] **Step 2: Run the focused artifact test to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-recording-compression "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingFileStoreTests
```

Expected: FAIL because `MeetingFileStore.createArtifacts` still returns `audio.wav`.

- [ ] **Step 3: Update `MeetingFileStore` to create `audio.m4a` artifacts**

Change `QuickMeeting/Services/MeetingFileStore.swift`:

```swift
return MeetingArtifacts(
    meetingFolderURL: meetingFolderURL,
    audioFileURL: meetingFolderURL.appendingPathComponent("audio.m4a")
)
```

- [ ] **Step 4: Run the focused artifact test to verify it passes**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-recording-compression "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingFileStoreTests
```

Expected: PASS with the updated artifact filename.

- [ ] **Step 5: Commit the artifact-path change**

```bash
git add QuickMeeting/Services/MeetingFileStore.swift QuickMeetingTests/MeetingFileStoreTests.swift
git commit -m "feat: save new meeting recordings as m4a"
```

### Task 2: Replace the WAV writer with an AAC/M4A writer at `96 kbps`

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeeting/Services/Recording/AudioCapturePipeline.swift`

- [ ] **Step 1: Write the failing native pipeline extension test**

In `QuickMeetingTests/AppViewModelTests.swift`, update the existing pipeline smoke test to use the new extension:

```swift
@Test
func startBuildsSystemAudioOnlySessionWithCanonicalWriterSettings() async throws {
    let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-audio.m4a")
    let session = AudioCaptureStreamSessionSpy()
    let writer = AudioFileWriterSpy()
    var requestedConfiguration: NativeAudioCapturePipeline.CaptureConfiguration?

    let pipeline = NativeAudioCapturePipeline(
        shareableContentProvider: {
            NativeAudioCapturePipeline.CaptureTarget(width: 1512, height: 982) {
                configuration,
                _
            in
                requestedConfiguration = configuration
                return session
            }
        },
        writerFactory: { requestedURL in
            writer.createdOutputURLs.append(requestedURL)
            return writer
        },
        captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration()
    )

    try await pipeline.start(outputURL: outputURL)
    try await pipeline.stop()

    #expect(writer.createdOutputURLs == [outputURL])
    #expect(writer.finishCallCount == 1)
    #expect(session.startCallCount == 1)
    #expect(session.stopCallCount == 1)
    #expect(
        requestedConfiguration == NativeAudioCapturePipeline.CaptureConfiguration(
            sampleRate: 48_000,
            channelCount: 2,
            capturesSystemAudio: true,
            capturesMicrophone: false
        )
    )
}
```

- [ ] **Step 2: Write the failing real-writer integration test**

Add this test near the other `NativeAudioCapturePipelineTests` in `QuickMeetingTests/AppViewModelTests.swift`:

```swift
@Test
func aacM4AAudioFileWriterCreatesReadableM4AFile() throws {
    let fileManager = FileManager.default
    let outputURL = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("sample.m4a")
    let writer = try AACM4AAudioFileWriter(outputURL: outputURL)
    let format = CanonicalAudioBufferConverter.canonicalFormat
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
    buffer.frameLength = 4_800

    if let channelData = buffer.floatChannelData {
        for frame in 0 ..< Int(buffer.frameLength) {
            channelData[0][frame] = 0.2
            channelData[1][frame] = 0.2
        }
    }

    try writer.append(buffer)
    try writer.finish()

    #expect(fileManager.fileExists(atPath: outputURL.path))

    let file = try AVAudioFile(forReading: outputURL)
    #expect(file.length > 0)
    #expect(outputURL.pathExtension == "m4a")
}
```

- [ ] **Step 3: Run the focused pipeline tests to verify at least one test fails for the right reason**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-recording-compression "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/AppViewModelTests/testStartBuildsSystemAudioOnlySessionWithCanonicalWriterSettings -only-testing:QuickMeetingTests/AppViewModelTests/testAacM4AAudioFileWriterCreatesReadableM4AFile
```

Expected: FAIL because the new writer type does not exist yet and the old test data still assumes `.wav`.

- [ ] **Step 4: Replace the WAV writer with an AAC writer in the recording pipeline**

In `QuickMeeting/Services/Recording/AudioCapturePipeline.swift`, change the convenience initializer:

```swift
convenience init() {
    self.init(
        shareableContentProvider: { try await Self.makeLiveCaptureTarget() },
        writerFactory: { try AACM4AAudioFileWriter(outputURL: $0) },
        captureConfiguration: CaptureConfiguration(capturesMicrophone: true)
    )
}
```

Replace the private WAV writer with an internal AAC writer:

```swift
final class AACM4AAudioFileWriter: NativeAudioCapturePipeline.AudioFileWriting {
    private static let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVEncoderBitRateKey: 96_000,
        AVNumberOfChannelsKey: 2,
        AVSampleRateKey: 48_000
    ]

    private var audioFile: AVAudioFile?

    init(outputURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: outputURL.path()) {
            try fileManager.removeItem(at: outputURL)
        }

        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: Self.outputSettings,
            commonFormat: CanonicalAudioBufferConverter.canonicalFormat.commonFormat,
            interleaved: CanonicalAudioBufferConverter.canonicalFormat.isInterleaved
        )
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        guard buffer.frameLength > 0 else {
            return
        }

        try audioFile?.write(from: buffer)
    }

    func finish() throws {
        audioFile = nil
    }
}
```

Also change any focused test URLs in `QuickMeetingTests/AppViewModelTests.swift` that represent newly created native pipeline output from `*.wav` to `*.m4a` so diagnostics and output-path assertions match the new default.

- [ ] **Step 5: Run the focused pipeline tests to verify they pass**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-recording-compression "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/AppViewModelTests/testStartBuildsSystemAudioOnlySessionWithCanonicalWriterSettings -only-testing:QuickMeetingTests/AppViewModelTests/testAacM4AAudioFileWriterCreatesReadableM4AFile
```

Expected: PASS with a readable `m4a` file and the pipeline smoke test still green.

- [ ] **Step 6: Commit the AAC writer change**

```bash
git add QuickMeeting/Services/Recording/AudioCapturePipeline.swift QuickMeetingTests/AppViewModelTests.swift
git commit -m "feat: compress recordings with aac m4a"
```

### Task 3: Run focused regression coverage and manual sanity verification

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeetingTests/MeetingFileStoreTests.swift`

- [ ] **Step 1: Run the combined focused regression suite**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-recording-compression "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingFileStoreTests -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS for the updated artifact and native recording pipeline tests, with no newly introduced failures in the focused suite.

- [ ] **Step 2: Inspect the focused failure tail if the suite fails**

Run only if Step 1 fails:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination "platform=macOS" -derivedDataPath .derived-data-recording-compression "CODE_SIGNING_ALLOWED=NO" "CODE_SIGNING_REQUIRED=NO" "CODE_SIGN_IDENTITY=" -only-testing:QuickMeetingTests/MeetingFileStoreTests -only-testing:QuickMeetingTests/AppViewModelTests | tail -n 60
```

Expected: A short failure tail that identifies the remaining broken assertion or compile error without pulling the full build transcript into context.

- [ ] **Step 3: Perform the manual recording sanity check**

Use the app manually and confirm all of the following:

```text
1. Start a short recording.
2. Stop the recording and open the meeting artifact folder.
3. Confirm the audio file is named audio.m4a.
4. Confirm the file size is materially smaller than a comparable WAV recording.
5. Play the meeting audio in the app and confirm playback works.
6. Run transcription for that meeting and confirm it completes successfully.
```

Expected: A compressed `audio.m4a` recording that still plays back and transcribes.

- [ ] **Step 4: Commit any final test-only cleanup if needed**

If no additional code changes were needed after Step 1, skip this step. Otherwise:

```bash
git add QuickMeetingTests/AppViewModelTests.swift QuickMeetingTests/MeetingFileStoreTests.swift
git commit -m "test: tighten recording compression coverage"
```

## Self-Review

- Spec coverage:
  - New `audio.m4a` artifact path is covered in Task 1.
  - AAC `96 kbps` writer replacement is covered in Task 2.
  - Mixed-format compatibility is preserved by changing only artifact creation and writer defaults, not any path-based consumers.
  - Focused automated verification and the required manual recording/transcription sanity check are covered in Task 3.
- Placeholder scan:
  - No `TODO`, `TBD`, or “handle appropriately” placeholders remain.
  - Every task includes exact files, concrete code, and exact commands.
- Type consistency:
  - The writer type is named `AACM4AAudioFileWriter` consistently across tests and implementation.
  - The existing `CanonicalAudioBufferConverter` remains the PCM source of truth for the new writer.

Offer after saving: start executing this plan with the TDD sequence above.
