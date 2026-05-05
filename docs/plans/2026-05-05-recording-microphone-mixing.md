**Goal:** Capture microphone audio alongside screen audio and save a single mixed meeting recording.

**Architecture:** Extend the native recording pipeline to ingest system audio and microphone audio as separate sources from ScreenCaptureKit, normalize both into the existing canonical PCM format, and mix them into one writer-owned WAV file. Keep the feature boundary unchanged for `AppViewModel` and `RecordingService` so the app still exposes one recording session and one saved audio artifact.

**Tech Stack:** Swift, ScreenCaptureKit, AVFAudio, CoreMedia, Swift Testing, xcodebuild

---

## File Map

- Modify: `QuickMeeting/Services/Recording/AudioCapturePipeline.swift`
  Responsibility: register system and microphone outputs, convert source sample buffers into canonical PCM, mix both sources into one stream, and preserve capture diagnostics.
- Modify: `QuickMeeting/QuickMeetingApp.swift`
  Responsibility: enable microphone capture in the live pipeline configuration.
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
  Responsibility: add red-green coverage for microphone-enabled session configuration and mixed multi-source audio handling.

## Task 1: Lock In Microphone Capture Configuration

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
    @Test
    func startBuildsSessionWithSystemAudioAndMicrophoneEnabled() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/native-pipeline-audio.wav")
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
            captureConfiguration: NativeAudioCapturePipeline.CaptureConfiguration(
                capturesSystemAudio: true,
                capturesMicrophone: true
            )
        )

        try await pipeline.start(outputURL: outputURL)
        try await pipeline.stop()

        #expect(
            requestedConfiguration == NativeAudioCapturePipeline.CaptureConfiguration(
                sampleRate: 48_000,
                channelCount: 2,
                capturesSystemAudio: true,
                capturesMicrophone: true
            )
        )
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-mic-mixing-red-1 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeAudioCapturePipelineTests/startBuildsSessionWithSystemAudioAndMicrophoneEnabled
```

Expected: FAIL because the default live configuration still disables microphone capture.

- [ ] **Step 3: Write the minimal implementation**

```swift
audioCapturePipeline: NativeAudioCapturePipeline(
    captureConfiguration: .init(
        capturesSystemAudio: true,
        capturesMicrophone: true
    )
)
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-mic-mixing-green-1 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeAudioCapturePipelineTests/startBuildsSessionWithSystemAudioAndMicrophoneEnabled
```

Expected: PASS for the new microphone-enabled configuration test.

## Task 2: Add Multi-Source Capture And Mixing

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeeting/Services/Recording/AudioCapturePipeline.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
    @Test
    func outputSinkMixesSystemAndMicrophoneAudioIntoSingleWriterStream() async throws {
        let writer = AudioFileWriterSpy()
        let sink = CaptureOutputSink(writer: writer)

        sink.appendForTesting(
            try SampleBufferFactory.makeStereoSampleBuffer(
                presentationTimeSeconds: 0,
                leftChannel: [0.25, 0.25],
                rightChannel: [0.25, 0.25]
            ),
            outputType: .audio
        )
        sink.appendForTesting(
            try SampleBufferFactory.makeStereoSampleBuffer(
                presentationTimeSeconds: 0,
                leftChannel: [0.50, 0.50],
                rightChannel: [0.50, 0.50]
            ),
            outputType: .microphone
        )

        _ = try await sink.finish()

        let buffer = try #require(writer.appendedBuffers.first)
        #expect(buffer.frameLength == 2)
        #expect(buffer.floatChannelData?[0][0] == 0.75)
        #expect(buffer.floatChannelData?[1][0] == 0.75)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-mic-mixing-red-2 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeAudioCapturePipelineTests/outputSinkMixesSystemAndMicrophoneAudioIntoSingleWriterStream
```

Expected: FAIL because the sink currently forwards raw sample buffers directly to the writer and has no concept of microphone output type or mixing.

- [ ] **Step 3: Write the minimal implementation**

```swift
private enum CapturedAudioSource {
    case system
    case microphone
}

protocol AudioFileWriting: AnyObject {
    func append(_ buffer: AVAudioPCMBuffer) throws
    func finish() throws
}

final class CapturedAudioMixer {
    func append(_ sampleBuffer: CMSampleBuffer, source: CapturedAudioSource) throws {
        let pcmBuffer = try sampleBuffer.makePCMBuffer()
        let canonicalBuffer = try canonicalizer.canonicalBuffer(from: pcmBuffer)
        try mixOrWrite(canonicalBuffer, source: source)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-mic-mixing-green-2 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeAudioCapturePipelineTests/outputSinkMixesSystemAndMicrophoneAudioIntoSingleWriterStream
```

Expected: PASS with one mixed canonical buffer written to the writer spy.

## Task 3: Register Dedicated Microphone Stream Output

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeeting/Services/Recording/AudioCapturePipeline.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
    @Test
    func screenCaptureSessionRegistersAudioAndMicrophoneOutputsWhenEnabled() throws {
        let stream = SCStreamSpy()
        let session = try ScreenCaptureAudioStreamSession(
            display: SCDisplayStub.make(),
            displayWidth: 1512,
            displayHeight: 982,
            captureConfiguration: .init(
                capturesSystemAudio: true,
                capturesMicrophone: true
            ),
            outputSink: CaptureOutputSink(writer: AudioFileWriterSpy()),
            streamFactory: { _, _, _ in stream }
        )

        #expect(stream.addedOutputTypes == [.audio, .microphone])
        _ = session
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-mic-mixing-red-3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeAudioCapturePipelineTests/screenCaptureSessionRegistersAudioAndMicrophoneOutputsWhenEnabled
```

Expected: FAIL because the live session currently only registers `.audio`.

- [ ] **Step 3: Write the minimal implementation**

```swift
if captureConfiguration.capturesSystemAudio {
    try stream.addStreamOutput(
        outputSink,
        type: .audio,
        sampleHandlerQueue: outputSink.sampleHandlerQueue
    )
}

if captureConfiguration.capturesMicrophone {
    try stream.addStreamOutput(
        outputSink,
        type: .microphone,
        sampleHandlerQueue: outputSink.sampleHandlerQueue
    )
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-mic-mixing-green-3 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeAudioCapturePipelineTests/screenCaptureSessionRegistersAudioAndMicrophoneOutputsWhenEnabled
```

Expected: PASS for the dedicated output registration test.

## Task 4: Verify The Recording Slice

**Files:**
- Modify: `QuickMeetingTests/AppViewModelTests.swift`
- Modify: `QuickMeeting/Services/Recording/AudioCapturePipeline.swift`
- Modify: `QuickMeeting/QuickMeetingApp.swift`
- Test: `QuickMeetingTests/AppViewModelTests.swift`

- [ ] **Step 1: Run the focused native recording tests**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-mic-mixing-verify CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/NativeAudioCapturePipelineTests
```

Expected: PASS for the microphone configuration, output registration, stop/retry, diagnostics, and mixer tests.

- [ ] **Step 2: Run the broader recording tests**

Run:

```bash
xcodebuild test -project QuickMeeting.xcodeproj -scheme QuickMeeting -destination 'platform=macOS' -derivedDataPath .derived-data-mic-mixing-verify CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= -only-testing:QuickMeetingTests/AppViewModelTests
```

Expected: PASS with no regressions in recording lifecycle behavior.

- [ ] **Step 3: Inspect the diff before handoff**

Run:

```bash
git diff -- QuickMeeting/Services/Recording/AudioCapturePipeline.swift QuickMeeting/QuickMeetingApp.swift QuickMeetingTests/AppViewModelTests.swift docs/plans/2026-05-05-recording-microphone-mixing.md
```

Expected: Diff shows the plan, microphone-enabled live pipeline, multi-source sink, and tests only.
