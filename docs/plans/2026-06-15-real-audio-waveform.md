**Goal:** Replace the fake sine-curve waveform in `WaveformPlayerBar` with real per-meeting amplitude data extracted from the audio file and stored in SwiftData.

**Architecture:** Extract 300 RMS amplitude samples from the recording with `AVAssetReader` (background actor), store them on the `Meeting` model (single optional `[Double]?` column), and downsample at render time to however many bars fit the available width. Extraction is skipped on every subsequent open — the cached values are read from SwiftData and used immediately. While extraction is running the first time, the existing sine placeholder shows.

**Tech Stack:** SwiftUI, AVFoundation, SwiftData, Swift Testing

---

## File Map

- **Modify:** `QuickMeeting/Views/QuickMeetingTheme.swift` — add `QMWaveform.resized(to:)` helper
- **Create:** `QuickMeetingTests/WaveformDisplayTests.swift` — tests for `QMWaveform.resized` and `waveformDisplayHeights`
- **Modify:** `QuickMeeting/Models/Meeting.swift` — add `waveformSamples: [Double]?` and `storeWaveform(_:updatedAt:)`
- **Modify:** `QuickMeetingTests/MeetingStoreTests.swift` — add `storeWaveform` persistence test
- **Modify:** `QuickMeeting/Services/MeetingStore.swift` — add `storeWaveform(meetingID:samples:) throws`
- **Create:** `QuickMeeting/Services/Playback/WaveformExtractor.swift` — background actor, `AVAssetReader`-based extraction
- **Create:** `QuickMeetingTests/WaveformExtractorTests.swift` — extraction correctness tests
- **Modify:** `QuickMeeting/Services/Playback/MeetingAudioPlayback.swift` — add `waveformSamples`, inject extractor, update `loadAudioFileDeferred`
- **Modify:** `QuickMeetingTests/MeetingAudioPlaybackTests.swift` — add waveform lifecycle tests
- **Modify:** `QuickMeeting/Views/WaveformPlayerBar.swift` — add `waveformSamples` param, full-width layout, `waveformDisplayHeights` free function
- **Modify:** `QuickMeeting/Views/MeetingDetailView.swift` — add `onStoreWaveform` callback, wire new params
- **Modify:** `QuickMeeting/ViewModels/AppViewModel.swift` — add `storeWaveform(meetingID:samples:)`
- **Modify:** `QuickMeeting/ContentView.swift` — pass `onStoreWaveform` to `MeetingDetailView`

---

## Task 1: `QMWaveform.resized(to:)` and display-height free function

**Files:**
- Modify: `QuickMeeting/Views/QuickMeetingTheme.swift`
- Create: `QuickMeetingTests/WaveformDisplayTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `QuickMeetingTests/WaveformDisplayTests.swift`:

```swift
import Testing
@testable import QuickMeeting

struct WaveformDisplayTests {
    // MARK: QMWaveform.resized

    @Test
    func resizedToSameCountReturnsOriginalValues() {
        let result = QMWaveform.resized(to: 74)
        #expect(result.count == 74)
        #expect(result == QMWaveform.heights)
    }

    @Test
    func resizedToMoreBarsInterpolatesWithinHeightRange() {
        let result = QMWaveform.resized(to: 150)
        #expect(result.count == 150)
        for h in result {
            #expect(h >= 4)
            #expect(h <= 30)
        }
    }

    @Test
    func resizedToFewerBarsAveragesWithinHeightRange() {
        let result = QMWaveform.resized(to: 30)
        #expect(result.count == 30)
        for h in result {
            #expect(h >= 4)
            #expect(h <= 30)
        }
    }

    @Test
    func resizedToZeroReturnsEmpty() {
        #expect(QMWaveform.resized(to: 0) == [])
    }

    // MARK: waveformDisplayHeights

    @Test
    func displayHeightsFromEmptySamplesReturnsSinePlaceholder() {
        let result = waveformDisplayHeights(from: [], displayCount: 74)
        #expect(result.count == 74)
        #expect(result == QMWaveform.heights)
    }

    @Test
    func displayHeightsFromNormalisedSamplesMapIntoExpectedRange() {
        let samples = [Double](repeating: 0.5, count: 300)
        let result = waveformDisplayHeights(from: samples, displayCount: 100)
        #expect(result.count == 100)
        for h in result {
            #expect(h >= 4)
            #expect(h <= 30)
        }
    }

    @Test
    func displayHeightsFromAllOnesReturnsMaxHeight() {
        let samples = [Double](repeating: 1.0, count: 300)
        let result = waveformDisplayHeights(from: samples, displayCount: 50)
        for h in result {
            #expect(abs(h - 30) < 0.01)
        }
    }

    @Test
    func displayHeightsFromAllZerosReturnsMinHeight() {
        let samples = [Double](repeating: 0.0, count: 300)
        let result = waveformDisplayHeights(from: samples, displayCount: 50)
        for h in result {
            #expect(abs(h - 4) < 0.01)
        }
    }

    @Test
    func displayHeightsCountMatchesRequestedDisplayCount() {
        let samples = [Double](repeating: 0.5, count: 300)
        #expect(waveformDisplayHeights(from: samples, displayCount: 1).count == 1)
        #expect(waveformDisplayHeights(from: samples, displayCount: 74).count == 74)
        #expect(waveformDisplayHeights(from: samples, displayCount: 200).count == 200)
        #expect(waveformDisplayHeights(from: samples, displayCount: 0).count == 0)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-waveform \
  -only-testing QuickMeetingTests/WaveformDisplayTests \
  -quiet 2>&1 | grep -E 'error:|warning:|passed|failed|Executed|SUCCEEDED|FAILED'
```

Expected: compile error — `QMWaveform.resized` and `waveformDisplayHeights` not defined.

- [ ] **Step 3: Add `QMWaveform.resized(to:)` to `QuickMeetingTheme.swift`**

In `QuickMeeting/Views/QuickMeetingTheme.swift`, replace the closing brace of `enum QMWaveform` at line 137:

```swift
/// Static sine-based waveform bar heights, matching the design's generator.
enum QMWaveform {
    static let heights: [CGFloat] = {
        (0..<74).map { i in
            let base = abs(sin(Double(i) * 0.55) * 0.62 + sin(Double(i) * 0.21) * 0.48 + sin(Double(i) * 1.3) * 0.22)
            return CGFloat(min(30, 4 + Int((base * 26).rounded())))
        }
    }()

    /// Resamples `heights` to `count` bars by averaging adjacent values.
    /// Used as a loading placeholder when real waveform samples are not yet available.
    static func resized(to count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let source = heights
        guard count != source.count else { return source }
        let ratio = Double(source.count) / Double(count)
        return (0..<count).map { i in
            let start = Int((Double(i) * ratio).rounded(.down))
            let end   = min(Int((Double(i + 1) * ratio).rounded(.up)), source.count)
            guard start < end else { return source[min(start, source.count - 1)] }
            let slice = source[start..<end]
            return slice.reduce(0, +) / CGFloat(slice.count)
        }
    }
}
```

- [ ] **Step 4: Add `waveformDisplayHeights` free function to `WaveformPlayerBar.swift`**

Add at the bottom of `QuickMeeting/Views/WaveformPlayerBar.swift` (outside the struct, after the closing brace):

```swift
/// Converts 300 stored amplitude samples into `displayCount` bar heights
/// in the 4...30 pt range used by `WaveformPlayerBar`.
/// Returns the sine placeholder when `samples` is empty (not yet extracted).
func waveformDisplayHeights(from samples: [Double], displayCount: Int) -> [CGFloat] {
    guard !samples.isEmpty else {
        return QMWaveform.resized(to: displayCount)
    }
    guard displayCount > 0 else { return [] }
    let ratio = Double(samples.count) / Double(displayCount)
    return (0..<displayCount).map { i in
        let start = Int((Double(i) * ratio).rounded(.down))
        let end   = min(Int((Double(i + 1) * ratio).rounded(.up)), samples.count)
        let slice = samples[start..<end]
        let avg   = slice.reduce(0, +) / Double(slice.count)
        return CGFloat(4 + avg * 26)
    }
}
```

- [ ] **Step 5: Run tests — expect all pass**

```bash
xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-waveform \
  -only-testing QuickMeetingTests/WaveformDisplayTests \
  -quiet 2>&1 | grep -E 'error:|warning:|passed|failed|Executed|SUCCEEDED|FAILED'
```

Expected: `Test Suite 'WaveformDisplayTests' passed`

- [ ] **Step 6: Commit**

```bash
git add QuickMeeting/Views/QuickMeetingTheme.swift \
        QuickMeeting/Views/WaveformPlayerBar.swift \
        QuickMeetingTests/WaveformDisplayTests.swift
git commit -m "Add QMWaveform.resized and waveformDisplayHeights for real waveform rendering"
```

---

## Task 2: `Meeting` model — `waveformSamples` attribute and mutation

**Files:**
- Modify: `QuickMeeting/Models/Meeting.swift`
- Modify: `QuickMeetingTests/MeetingStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `QuickMeetingTests/MeetingStoreTests.swift` (inside the `struct MeetingStoreTests` body):

```swift
@Test
func newMeetingHasNilWaveformSamples() throws {
    let schema = Schema([
        Meeting.self, PersistedTranscriptSpeaker.self,
        PersistedTranscriptSegment.self, PersistedKnownSpeaker.self,
        PersistedKnownSpeakerCentroid.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    let store = MeetingStore(modelContext: ModelContext(container))

    let folderURL = URL(fileURLWithPath: "/tmp/meeting-wf")
    let audioURL = folderURL.appendingPathComponent("audio.m4a")
    let meeting = try store.createMeeting(
        title: "Waveform Test",
        startedAt: Date(),
        folderURL: folderURL,
        audioFileURL: audioURL
    )

    #expect(meeting.waveformSamples == nil)
}

@Test
func storeWaveformPersistsSamplesAcrossContexts() throws {
    let schema = Schema([
        Meeting.self, PersistedTranscriptSpeaker.self,
        PersistedTranscriptSegment.self, PersistedKnownSpeaker.self,
        PersistedKnownSpeakerCentroid.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    let store = MeetingStore(modelContext: context)

    let folderURL = URL(fileURLWithPath: "/tmp/meeting-wf2")
    let audioURL = folderURL.appendingPathComponent("audio.m4a")
    let meeting = try store.createMeeting(
        title: "Waveform Persist",
        startedAt: Date(),
        folderURL: folderURL,
        audioFileURL: audioURL
    )

    let samples = (0..<300).map { Double($0) / 299.0 }
    try store.storeWaveform(meetingID: meeting.id, samples: samples)

    let verificationStore = MeetingStore(modelContext: ModelContext(container))
    let reloaded = try verificationStore.fetchMeeting(id: meeting.id)
    #expect(reloaded.waveformSamples?.count == 300)
    #expect(abs((reloaded.waveformSamples?.last ?? -1) - 1.0) < 0.001)
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-waveform \
  -only-testing QuickMeetingTests/MeetingStoreTests/newMeetingHasNilWaveformSamples \
  -quiet 2>&1 | grep -E 'error:|warning:|passed|failed|Executed|SUCCEEDED|FAILED'
```

Expected: compile error — `waveformSamples` not a member of `Meeting`.

- [ ] **Step 3: Add `waveformSamples` and `storeWaveform` to `Meeting`**

In `QuickMeeting/Models/Meeting.swift`, add the new stored property after `private(set) var updatedAt: Date` (line 31):

```swift
    private(set) var waveformSamples: [Double]?
```

Add the new mutation method after `failTranscription` (before the final `private func touch`):

```swift
    func storeWaveform(_ samples: [Double], updatedAt: Date = Date()) {
        waveformSamples = samples
        touch(updatedAt: updatedAt)
    }
```

- [ ] **Step 4: Add `storeWaveform` to `MeetingStore`**

In `QuickMeeting/Services/MeetingStore.swift`, add after `failTranscription`:

```swift
    func storeWaveform(meetingID: UUID, samples: [Double]) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.storeWaveform(samples, updatedAt: Date())
        try modelContext.save()
    }
```

- [ ] **Step 5: Run tests — expect pass**

```bash
xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-waveform \
  -only-testing QuickMeetingTests/MeetingStoreTests/newMeetingHasNilWaveformSamples \
  -only-testing QuickMeetingTests/MeetingStoreTests/storeWaveformPersistsSamplesAcrossContexts \
  -quiet 2>&1 | grep -E 'error:|warning:|passed|failed|Executed|SUCCEEDED|FAILED'
```

Expected: both tests pass.

- [ ] **Step 6: Commit**

```bash
git add QuickMeeting/Models/Meeting.swift \
        QuickMeeting/Services/MeetingStore.swift \
        QuickMeetingTests/MeetingStoreTests.swift
git commit -m "Add waveformSamples to Meeting model and MeetingStore.storeWaveform"
```

---

## Task 3: `WaveformExtractor` background actor

**Files:**
- Create: `QuickMeeting/Services/Playback/WaveformExtractor.swift`
- Create: `QuickMeetingTests/WaveformExtractorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `QuickMeetingTests/WaveformExtractorTests.swift`:

```swift
import Foundation
import Testing
@testable import QuickMeeting

struct WaveformExtractorTests {
    // Writes a minimal mono 16-bit PCM WAV to the given URL.
    func writeWAV(samples: [Float], sampleRate: Int = 44100, to url: URL) throws {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = UInt32(samples.count) * 2
        let chunkSize = UInt32(36) + dataSize

        var bytes = Data()
        func le<T: FixedWidthInteger>(_ v: T) {
            withUnsafeBytes(of: v.littleEndian) { bytes.append(contentsOf: $0) }
        }
        bytes.append(contentsOf: "RIFF".utf8); le(chunkSize)
        bytes.append(contentsOf: "WAVE".utf8)
        bytes.append(contentsOf: "fmt ".utf8); le(UInt32(16))
        le(UInt16(1)); le(numChannels)
        le(UInt32(sampleRate)); le(byteRate); le(blockAlign); le(bitsPerSample)
        bytes.append(contentsOf: "data".utf8); le(dataSize)
        for s in samples {
            le(Int16(max(-32_768, min(32_767, Int(s * 32_767)))))
        }
        try bytes.write(to: url)
    }

    @Test
    func extractReturnsExactly300ValuesForAValidFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        // 2 seconds of constant 0.5 amplitude
        let samples = [Float](repeating: 0.5, count: 44100 * 2)
        try writeWAV(samples: samples, to: url)

        let result = await WaveformExtractor().extract(from: url)
        let values = try #require(result)
        #expect(values.count == 300)
    }

    @Test
    func extractNormalisesResultSoMaxIsOne() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        var samples = [Float](repeating: 0.2, count: 44100)
        samples += [Float](repeating: 0.8, count: 44100)
        try writeWAV(samples: samples, to: url)

        let result = await WaveformExtractor().extract(from: url)
        let values = try #require(result)
        let peak = values.max() ?? 0
        #expect(abs(peak - 1.0) < 0.01)
    }

    @Test
    func extractResultValuesAreAllInZeroToOneRange() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        // alternating amplitudes
        let samples: [Float] = (0..<44100 * 3).map { Float($0 % 100) / 100.0 }
        try writeWAV(samples: samples, to: url)

        let result = await WaveformExtractor().extract(from: url)
        let values = try #require(result)
        for v in values {
            #expect(v >= 0.0)
            #expect(v <= 1.0)
        }
    }

    @Test
    func extractSilenceReturnsAllZeros() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = [Float](repeating: 0.0, count: 44100)
        try writeWAV(samples: samples, to: url)

        let result = await WaveformExtractor().extract(from: url)
        let values = try #require(result)
        for v in values {
            #expect(v == 0.0)
        }
    }

    @Test
    func extractMissingFileReturnsNil() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-missing.wav")
        let result = await WaveformExtractor().extract(from: url)
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-waveform \
  -only-testing QuickMeetingTests/WaveformExtractorTests \
  -quiet 2>&1 | grep -E 'error:|warning:|passed|failed|Executed|SUCCEEDED|FAILED'
```

Expected: compile error — `WaveformExtractor` not defined.

- [ ] **Step 3: Create `WaveformExtractor.swift`**

Create `QuickMeeting/Services/Playback/WaveformExtractor.swift`:

```swift
import AVFoundation
import CoreMedia
import Foundation

actor WaveformExtractor {
    static let sampleCount = 300

    func extract(from url: URL) async -> [Double]? {
        let asset = AVURLAsset(url: url)

        async let durationLoad = asset.load(.duration)
        async let tracksLoad  = asset.loadTracks(withMediaType: .audio)

        guard let duration = try? await durationLoad,
              let tracks   = try? await tracksLoad,
              let track    = tracks.first,
              duration.seconds > 0 else { return nil }

        let outputSettings: [String: Any] = [
            AVFormatIDKey:             Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey:    32,
            AVLinearPCMIsFloatKey:     true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return nil }

        let bucketDuration = duration.seconds / Double(Self.sampleCount)
        var buckets = [BucketAccumulator](repeating: BucketAccumulator(), count: Self.sampleCount)

        var sampleRate      = 48_000.0
        var channelsPerFrame = 2
        var rateDetected    = false
        var framesRead      = 0

        while let cmBuffer = output.copyNextSampleBuffer() {
            if !rateDetected,
               let fmt  = CMSampleBufferGetFormatDescription(cmBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee {
                sampleRate       = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48_000
                channelsPerFrame = Int(asbd.mChannelsPerFrame) > 0 ? Int(asbd.mChannelsPerFrame) : 2
                rateDetected     = true
            }

            guard let block = CMSampleBufferGetDataBuffer(cmBuffer) else { continue }
            let byteLen    = CMBlockBufferGetDataLength(block)
            let totalFloats = byteLen / MemoryLayout<Float>.size
            let frames     = totalFloats / max(channelsPerFrame, 1)
            guard frames > 0 else { continue }

            var raw = [Float](repeating: 0, count: totalFloats)
            raw.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteLen,
                                          destination: ptr.baseAddress!)
            }

            for frame in 0 ..< frames {
                let t  = Double(framesRead + frame) / sampleRate
                let bi = min(Int(t / bucketDuration), Self.sampleCount - 1)
                var s2 = 0.0
                for ch in 0 ..< channelsPerFrame {
                    let v = Double(raw[frame * channelsPerFrame + ch])
                    s2 += v * v
                }
                buckets[bi].add(squareSum: s2 / Double(channelsPerFrame))
            }
            framesRead += frames
        }

        guard reader.status == .completed else { return nil }

        var rms = buckets.map(\.rms)
        let peak = rms.max() ?? 0
        if peak > 0 { rms = rms.map { $0 / peak } }
        return rms
    }
}

private struct BucketAccumulator {
    var sumOfSquares = 0.0
    var count        = 0

    mutating func add(squareSum: Double) {
        sumOfSquares += squareSum
        count        += 1
    }

    var rms: Double {
        count > 0 ? sqrt(sumOfSquares / Double(count)) : 0
    }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-waveform \
  -only-testing QuickMeetingTests/WaveformExtractorTests \
  -quiet 2>&1 | grep -E 'error:|warning:|passed|failed|Executed|SUCCEEDED|FAILED'
```

Expected: all 5 tests pass. (WAV-based tests hit real `AVAssetReader` — no mocking needed.)

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Playback/WaveformExtractor.swift \
        QuickMeetingTests/WaveformExtractorTests.swift
git commit -m "Add WaveformExtractor actor for background RMS extraction"
```

---

## Task 4: `MeetingAudioPlayback` — waveform lifecycle

**Files:**
- Modify: `QuickMeeting/Services/Playback/MeetingAudioPlayback.swift`
- Modify: `QuickMeetingTests/MeetingAudioPlaybackTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `QuickMeetingTests/MeetingAudioPlaybackTests.swift` (inside `struct MeetingAudioPlaybackTests`):

```swift
    @Test
    func existingSamplesAreUsedImmediatelyWithoutExtraction() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        var extractorCallCount = 0
        let preloaded = [Double](repeating: 0.7, count: 300)
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { _ in NativeAudioPlayerSpy() },
            waveformExtractor: { _ in
                extractorCallCount += 1
                return nil
            }
        )

        await playback.loadAudioFileDeferred(
            at: audioURL,
            existingSamples: preloaded,
            onWaveformExtracted: { _ in }
        )

        #expect(playback.waveformSamples == preloaded)
        #expect(extractorCallCount == 0)
    }

    @Test
    func missingExistingSamplesTriggersExtractionAndCallsCallback() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        let extracted = [Double](repeating: 0.42, count: 300)
        var callbackSamples: [Double]?

        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { _ in NativeAudioPlayerSpy() },
            waveformExtractor: { _ in extracted }
        )

        await playback.loadAudioFileDeferred(
            at: audioURL,
            existingSamples: nil,
            onWaveformExtracted: { samples in callbackSamples = samples }
        )

        // Give the detached extraction task a moment to complete
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(playback.waveformSamples == extracted)
        #expect(callbackSamples == extracted)
    }

    @Test
    func failedExtractionLeavesWaveformSamplesEmpty() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        var callbackCalled = false
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { _ in NativeAudioPlayerSpy() },
            waveformExtractor: { _ in nil }  // extraction fails
        )

        await playback.loadAudioFileDeferred(
            at: audioURL,
            existingSamples: nil,
            onWaveformExtracted: { _ in callbackCalled = true }
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(playback.waveformSamples.isEmpty)
        #expect(callbackCalled == false)
    }
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-waveform \
  -only-testing QuickMeetingTests/MeetingAudioPlaybackTests/existingSamplesAreUsedImmediatelyWithoutExtraction \
  -quiet 2>&1 | grep -E 'error:|warning:|passed|failed|Executed|SUCCEEDED|FAILED'
```

Expected: compile error — `waveformSamples`, `waveformExtractor` parameter, and new `loadAudioFileDeferred` signature not defined.

- [ ] **Step 3: Update `MeetingAudioPlayback`**

In `QuickMeeting/Services/Playback/MeetingAudioPlayback.swift`:

**Add published property** (after `@Published private(set) var duration: TimeInterval = 0`):

```swift
    @Published private(set) var waveformSamples: [Double] = []
```

**Add stored property** (after `private var progressTimer: Timer?`):

```swift
    private let waveformExtractor: @Sendable (URL) async -> [Double]?
    private var currentAudioURL: URL?
```

**Add `waveformExtractor` parameter to `init`** (after `deferredLoadHook` parameter):

```swift
        waveformExtractor: @escaping @Sendable (URL) async -> [Double]? = { url in
            await WaveformExtractor().extract(from: url)
        }
```

Add the assignment in the init body (after `self.deferredLoadHook = deferredLoadHook`):

```swift
        self.waveformExtractor = waveformExtractor
```

**Replace `loadAudioFileDeferred`** with:

```swift
    func loadAudioFileDeferred(
        at fileURL: URL,
        existingSamples: [Double]? = nil,
        onWaveformExtracted: @escaping @MainActor ([Double]) -> Void = { _ in }
    ) async {
        await deferredLoadHook()
        guard !Task.isCancelled else { return }

        currentAudioURL = fileURL

        do {
            try loadAudioFile(at: fileURL)
        } catch {
            nativePlayer = nil
            duration = 0
            currentTime = 0
            state = .failed(message: error.localizedDescription)
        }

        if let samples = existingSamples {
            waveformSamples = samples
            return
        }

        let capturedURL = fileURL
        Task.detached { [weak self, waveformExtractor] in
            guard let samples = await waveformExtractor(capturedURL) else { return }
            await MainActor.run { [weak self] in
                guard let self, self.currentAudioURL == capturedURL else { return }
                self.waveformSamples = samples
                onWaveformExtracted(samples)
            }
        }
    }
```

- [ ] **Step 4: Run all playback tests**

```bash
xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-waveform \
  -only-testing QuickMeetingTests/MeetingAudioPlaybackTests \
  -quiet 2>&1 | grep -E 'error:|warning:|passed|failed|Executed|SUCCEEDED|FAILED'
```

Expected: all tests pass (existing tests still compile because `existingSamples` and `onWaveformExtracted` have defaults).

- [ ] **Step 5: Commit**

```bash
git add QuickMeeting/Services/Playback/MeetingAudioPlayback.swift \
        QuickMeetingTests/MeetingAudioPlaybackTests.swift
git commit -m "Add waveformSamples and injectable extractor to MeetingAudioPlayback"
```

---

## Task 5: `WaveformPlayerBar` — full-width layout and real samples

**Files:**
- Modify: `QuickMeeting/Views/WaveformPlayerBar.swift`

(The `waveformDisplayHeights` free function was already added in Task 1.)

- [ ] **Step 1: Add `waveformSamples` parameter and update the `waveform` computed property**

Replace the entire contents of `QuickMeeting/Views/WaveformPlayerBar.swift` with:

```swift
//
//  WaveformPlayerBar.swift
//  QuickMeeting
//

import SwiftUI

struct WaveformPlayerBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let isAvailable: Bool
    let waveformSamples: [Double]
    let onToggle: () -> Void
    /// Called with a 0...1 fraction of the timeline.
    let onSeek: (Double) -> Void

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(QMTheme.sage, in: Circle())
                    .shadow(color: QMTheme.sage.opacity(0.45), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .opacity(isAvailable ? 1 : 0.5)

            waveform

            Text("\(timeString(currentTime)) / \(timeString(duration))")
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundStyle(QMTheme.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(QMTheme.cardBorder, lineWidth: 1))
        .shadow(color: Color(hex: "#28241e").opacity(0.18), radius: 16, y: 10)
    }

    private var waveform: some View {
        GeometryReader { proxy in
            let barStride: CGFloat = 5  // 3 px bar + 2 px gap
            let displayCount = max(1, Int(proxy.size.width / barStride))
            let heights = waveformDisplayHeights(from: waveformSamples, displayCount: displayCount)
            HStack(spacing: 2) {
                ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                    Capsule()
                        .fill(Double(index) / Double(displayCount) < fraction
                              ? QMTheme.sage : QMTheme.recordedDot)
                        .frame(width: 3, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard isAvailable, proxy.size.width > 0 else { return }
                        onSeek(min(1, max(0, value.location.x / proxy.size.width)))
                    }
            )
        }
        .frame(maxWidth: .infinity, height: 34)
    }

    private func timeString(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

Note the two layout changes from the original:
1. `waveformSamples` parameter replaces implicit `QMWaveform.heights` usage
2. `.frame(height: 34)` → `.frame(maxWidth: .infinity, height: 34)` so the waveform fills remaining HStack width

- [ ] **Step 2: Run the full test suite to confirm no regressions**

```bash
xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-waveform \
  -quiet 2>&1 | grep -E 'error:|warning:|passed|failed|Executed|SUCCEEDED|FAILED'
```

Expected: all tests pass. (The view doesn't compile-break anything — it will fail to compile at `MeetingDetailView` call sites but those don't have compilation tests here.)

- [ ] **Step 3: Commit**

```bash
git add QuickMeeting/Views/WaveformPlayerBar.swift
git commit -m "WaveformPlayerBar: real samples param, full-width waveform, dynamic bar count"
```

---

## Task 6: Wire `AppViewModel`, `MeetingDetailView`, and `ContentView`

**Files:**
- Modify: `QuickMeeting/ViewModels/AppViewModel.swift`
- Modify: `QuickMeeting/Views/MeetingDetailView.swift`
- Modify: `QuickMeeting/ContentView.swift`

- [ ] **Step 1: Add `storeWaveform` to `AppViewModel`**

In `QuickMeeting/ViewModels/AppViewModel.swift`, add after `renameMeeting`:

```swift
    func storeWaveform(meetingID: UUID, samples: [Double]) {
        try? meetingStore.storeWaveform(meetingID: meetingID, samples: samples)
    }
```

- [ ] **Step 2: Add `onStoreWaveform` to `MeetingDetailView`**

In `QuickMeeting/Views/MeetingDetailView.swift`, add to the property list (after `onRenameSpeaker`):

```swift
    let onStoreWaveform: ([Double]) -> Void
```

- [ ] **Step 3: Update the audio load task in `MeetingDetailView`**

Replace the existing `.task(id: meetingAudioReloadKey(for: meeting))` modifier:

```swift
        .task(id: meetingAudioReloadKey(for: meeting)) {
            await playback.loadAudioFileDeferred(
                at: URL(fileURLWithPath: meeting.audioFilePath),
                existingSamples: meeting.waveformSamples,
                onWaveformExtracted: { samples in
                    onStoreWaveform(samples)
                }
            )
        }
```

- [ ] **Step 4: Pass `waveformSamples` to both `WaveformPlayerBar` call sites in `MeetingDetailView`**

There are two places `WaveformPlayerBar` is created. Find both and add `waveformSamples: playback.waveformSamples`:

**In `transcribedView`** (the overlay at the bottom of the transcript scroll):

```swift
            WaveformPlayerBar(
                currentTime: playback.currentTime,
                duration: playback.duration,
                isPlaying: playback.state == .playing,
                isAvailable: playback.isPlaybackAvailable,
                waveformSamples: playback.waveformSamples,
                onToggle: playback.togglePlayback,
                onSeek: seek(toFraction:)
            )
```

**In `recordedView`** (the player shown above the "Not transcribed yet" message):

```swift
            WaveformPlayerBar(
                currentTime: playback.currentTime,
                duration: playback.duration,
                isPlaying: playback.state == .playing,
                isAvailable: playback.isPlaybackAvailable,
                waveformSamples: playback.waveformSamples,
                onToggle: playback.togglePlayback,
                onSeek: seek(toFraction:)
            )
```

- [ ] **Step 5: Pass `onStoreWaveform` in `ContentView`**

In `QuickMeeting/ContentView.swift`, add `onStoreWaveform` to the `MeetingDetailView(...)` initialiser call (after `onRenameSpeaker`):

```swift
                        onStoreWaveform: { samples in
                            appViewModel.storeWaveform(
                                meetingID: selectedMeeting.id,
                                samples: samples
                            )
                        }
```

- [ ] **Step 6: Build and verify no compile errors**

```bash
xcodebuild build \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-waveform \
  -quiet 2>&1 | grep -E 'error:|warning:|SUCCEEDED|FAILED'
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 7: Run the full test suite**

```bash
xcodebuild test \
  -project QuickMeeting.xcodeproj \
  -scheme QuickMeeting \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-data-waveform \
  -quiet 2>&1 | grep -E 'error:|warning:|passed|failed|Executed|SUCCEEDED|FAILED'
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add QuickMeeting/ViewModels/AppViewModel.swift \
        QuickMeeting/Views/MeetingDetailView.swift \
        QuickMeeting/ContentView.swift
git commit -m "Wire real waveform extraction through AppViewModel, MeetingDetailView, ContentView"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task covering it |
|---|---|
| Extract 300 RMS samples via `AVAssetReader` | Task 3 (`WaveformExtractor`) |
| Store on `Meeting.waveformSamples: [Double]?` in SwiftData | Task 2 |
| `MeetingStore.storeWaveform` | Task 2 |
| Load from cache on subsequent opens | Task 4 (`existingSamples` path) |
| Sine placeholder while loading | Task 1 (`QMWaveform.resized`) + Task 5 (empty → placeholder) |
| Downsample 300→N at render time via `GeometryReader` | Task 1 (`waveformDisplayHeights`) + Task 5 |
| Full-width waveform (not fixed 74 bars) | Task 5 (`.frame(maxWidth: .infinity)` + dynamic `displayCount`) |
| `onStoreWaveform` callback pattern | Task 6 |
| No re-extraction if `existingSamples` is non-nil | Task 4 (`currentAudioURL` guard) |
| Failed extraction shows placeholder silently | Task 4 (nil → empty `waveformSamples` → placeholder in Task 5) |

All requirements covered. No gaps found.

**Placeholder scan:** No TBDs, no "implement later", no references to undefined types.

**Type consistency:**
- `waveformSamples: [Double]` used consistently across `Meeting`, `MeetingAudioPlayback`, `MeetingDetailView`
- `waveformDisplayHeights(from:displayCount:) -> [CGFloat]` defined in Task 1, used in Task 5
- `QMWaveform.resized(to:) -> [CGFloat]` defined in Task 1, used in `waveformDisplayHeights`
- `WaveformExtractor().extract(from:) async -> [Double]?` defined in Task 3, injected in Task 4
- `MeetingStore.storeWaveform(meetingID:samples:) throws` defined in Task 2, called in Task 6
- `AppViewModel.storeWaveform(meetingID:samples:)` defined in Task 6, wired in Task 6
