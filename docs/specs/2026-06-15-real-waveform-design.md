# Real Audio Waveform Design

**Date:** 2026-06-15
**Status:** Approved

## Problem

`WaveformPlayerBar` currently renders a fixed 74-bar sine curve (`QMWaveform.heights`) that is identical for every meeting. The waveform should reflect the actual audio content of each recording, fill the full available width of the player bar, and be ready for future layout changes without re-extracting audio.

---

## Solution Overview

1. Extract 300 RMS amplitude samples from the audio file using `AVAssetReader` on a background actor.
2. Store the 300 samples on the `Meeting` SwiftData model.
3. At render time, downsample the 300 stored samples to however many bars fit in the available pixel width.
4. While samples are loading (first open), show the existing sine placeholder.

---

## Data Model

### `Meeting` — new attribute

```swift
private(set) var waveformSamples: [Double]?
```

- `nil` = not yet extracted (triggers extraction on next open)
- Non-nil = 300 `Double` values in `0.0...1.0`, normalized so the loudest bar = 1.0
- SwiftData migrates this automatically as an optional additive column — no migration version file needed
- Deleted with the meeting via `modelContext.delete(meeting)` — no orphan risk

New mutation method on `Meeting`:

```swift
func storeWaveform(_ samples: [Double], updatedAt: Date = Date())
```

### `MeetingStore` — new method

```swift
func storeWaveform(meetingID: UUID, samples: [Double]) throws
```

Fetches the meeting and calls `storeWaveform(_:updatedAt:)`, then saves.

---

## Waveform Extraction

### `WaveformExtractor` — new background actor

Responsibility: given an audio file URL, return 300 normalized RMS values.

**Algorithm:**
1. Open the file with `AVURLAsset` and create an `AVAssetReader`.
2. Add an `AVAssetReaderTrackOutput` for the first audio track, requesting `Float32` non-interleaved PCM via `AVLinearPCMCodecType` output settings.
3. Read all sample buffers, accumulating raw `Float` samples.
4. Split the total sample stream into 300 equal-length chunks. Compute the RMS of each chunk: `sqrt(mean(sample²))`.
5. Normalize: divide all 300 RMS values by the maximum value (or 1.0 if max is 0) so the loudest chunk = 1.0.
6. Return `[Double]` (300 elements).

**Isolation:** `actor WaveformExtractor` — extraction runs off the main thread, result published back via `await`.

**Error handling:** if extraction fails for any reason (file missing, format unsupported, etc.), return `nil` silently. The view falls back to the sine placeholder indefinitely — no crash, no error shown.

---

## Playback Layer

### `MeetingAudioPlayback` — additions

```swift
@Published private(set) var waveformSamples: [Double] = []
```

Updated signature:

```swift
func loadAudioFileDeferred(
    at fileURL: URL,
    existingSamples: [Double]?,
    onWaveformExtracted: @escaping @MainActor ([Double]) -> Void
) async
```

**Behavior on call:**
- If `existingSamples` is non-nil (cached), assign to `waveformSamples` immediately — no extraction.
- If `existingSamples` is nil, load the player as usual, then in a detached background task call `WaveformExtractor.extract(from: fileURL)`. On completion, assign to `waveformSamples` and call `onWaveformExtracted` so the caller can persist.
- If the task is cancelled before extraction finishes, skip the callback.

---

## View Layer

### `WaveformPlayerBar` — changes

**New parameter** (replaces implicit `QMWaveform.heights` reference):

```swift
let waveformSamples: [Double]
```

**Layout change — full-width waveform:**

Current:
```
[play] [74 fixed bars left-aligned] [timer]
```

New:
```
[play] [bars fill all remaining width] [timer]
```

The `GeometryReader` already present for seek handling provides `proxy.size.width`. Use it:

```swift
let barStride: CGFloat = 5          // 3px bar + 2px gap
let displayCount = max(1, Int(proxy.size.width / barStride))
let displayHeights = downsample(waveformSamples, to: displayCount)
```

**Downsampling function** (pure, no side-effects):

```swift
private func downsample(_ samples: [Double], to count: Int) -> [CGFloat] {
    guard !samples.isEmpty else {
        // fall back to sine placeholder while loading
        return QMWaveform.resized(to: count)
    }
    let ratio = Double(samples.count) / Double(count)
    return (0..<count).map { i in
        let start = Int((Double(i) * ratio).rounded(.down))
        let end   = min(Int((Double(i + 1) * ratio).rounded(.up)), samples.count)
        let slice = samples[start..<end]
        let avg   = slice.reduce(0, +) / Double(slice.count)
        return CGFloat(4 + avg * 26)   // maps 0...1 → 4...30 px (same range as current sine bars)
    }
}
```

**`QMWaveform`** gains a helper used only as a placeholder:

```swift
static func resized(to count: Int) -> [CGFloat] { ... }  // resamples the 74-bar array to `count`
```

**`QMWaveform.heights`** stays as-is so no other callsites break.

### `MeetingDetailView` — wiring

The `.task` that loads audio gains the new arguments:

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

New callback parameter on `MeetingDetailView`:

```swift
let onStoreWaveform: ([Double]) -> Void
```

`WaveformPlayerBar` call sites in the view gain the new parameter:

```swift
WaveformPlayerBar(
    ...,
    waveformSamples: playback.waveformSamples
)
```

### `AppViewModel` — wiring

New method:

```swift
func storeWaveform(meetingID: UUID, samples: [Double]) {
    try? meetingStore.storeWaveform(meetingID: meetingID, samples: samples)
}
```

Passed as `onStoreWaveform` when constructing `MeetingDetailView`.

---

## Migration & Backward Compatibility

- All existing meetings start with `waveformSamples == nil`.
- On first open, extraction runs in the background; the sine placeholder shows until it completes (a few seconds).
- On every subsequent open, cached samples load instantly with no extraction.
- No manual migration file. SwiftData handles optional attribute addition automatically.

---

## Out of Scope

- Variable bar width (3 px fixed for now)
- Variable gap width (2 px fixed for now)
- Re-extraction when the audio file changes (not a current feature)
- Waveform display during live recording (uses `LiveWaveform` already)
