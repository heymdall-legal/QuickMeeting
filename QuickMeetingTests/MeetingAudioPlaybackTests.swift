import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct MeetingAudioPlaybackTests {
    actor DeferredLoadGate {
        private var continuations = [CheckedContinuation<Void, Never>]()

        func wait() async {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }

        func open() {
            let pendingContinuations = continuations
            continuations.removeAll()
            pendingContinuations.forEach { $0.resume() }
        }
    }

    final class NativeAudioPlayerSpy: NativeAudioPlaying {
        private(set) var loadedURL: URL?
        private(set) var playCallCount = 0
        private(set) var pauseCallCount = 0
        private(set) var stopCallCount = 0
        private(set) var prepareToPlayCallCount = 0
        var duration: TimeInterval = 0
        var currentTime: TimeInterval = 0
        var onFinishPlayback: (() -> Void)?

        func markLoaded(url: URL) {
            loadedURL = url
        }

        func play() {
            playCallCount += 1
        }

        func pause() {
            pauseCallCount += 1
        }

        func stop() {
            stopCallCount += 1
        }

        func prepareToPlay() {
            prepareToPlayCallCount += 1
        }

        func finishPlayback() {
            onFinishPlayback?()
        }
    }

    @Test
    func loadReadyFileTransitionsToReadyState() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        let nativePlayer = NativeAudioPlayerSpy()
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                nativePlayer.markLoaded(url: url)
                return nativePlayer
            }
        )

        try playback.loadAudioFile(at: audioURL)

        #expect(playback.state == .ready)
        #expect(nativePlayer.loadedURL == audioURL)
        #expect(nativePlayer.prepareToPlayCallCount == 1)
        #expect(playback.duration == 0)
        #expect(playback.currentTime == 0)
    }

    @Test
    func deferredLoadWaitsUntilGateOpensBeforePreparingPlayer() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        let gate = DeferredLoadGate()
        let nativePlayer = NativeAudioPlayerSpy()
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                nativePlayer.markLoaded(url: url)
                return nativePlayer
            },
            deferredLoadHook: {
                await gate.wait()
            }
        )

        let loadingTask = Task {
            await playback.loadAudioFileDeferred(at: audioURL)
        }

        await Task.yield()

        #expect(nativePlayer.loadedURL == nil)
        #expect(nativePlayer.prepareToPlayCallCount == 0)
        #expect(playback.state == .idle)

        await gate.open()
        await loadingTask.value

        #expect(nativePlayer.loadedURL == audioURL)
        #expect(nativePlayer.prepareToPlayCallCount == 1)
        #expect(playback.state == .ready)
    }

    @Test
    func togglePlaybackMovesBetweenPlayingAndPausedStates() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        let nativePlayer = NativeAudioPlayerSpy()
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                nativePlayer.markLoaded(url: url)
                return nativePlayer
            }
        )

        try playback.loadAudioFile(at: audioURL)
        playback.togglePlayback()

        #expect(playback.state == .playing)
        #expect(nativePlayer.playCallCount == 1)

        playback.togglePlayback()

        #expect(playback.state == .paused)
        #expect(nativePlayer.pauseCallCount == 1)
    }

    @Test
    func loadMissingFileProducesFriendlyFailureState() throws {
        let fileManager = FileManager.default
        let missingURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("missing.wav")
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                let player = NativeAudioPlayerSpy()
                player.markLoaded(url: url)
                return player
            }
        )

        try playback.loadAudioFile(at: missingURL)

        #expect(playback.state == .failed(message: "Recording file is missing."))
    }

    @Test
    func loadNewFileStopsCurrentPlaybackAndPreparesNewSelection() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let firstURL = rootURL.appendingPathComponent("first.wav")
        let secondURL = rootURL.appendingPathComponent("second.wav")
        fileManager.createFile(atPath: firstURL.path, contents: Data("first".utf8))
        fileManager.createFile(atPath: secondURL.path, contents: Data("second".utf8))

        let firstPlayer = NativeAudioPlayerSpy()
        let secondPlayer = NativeAudioPlayerSpy()
        var queuedPlayers = [firstPlayer, secondPlayer]
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                let player = queuedPlayers.removeFirst()
                player.markLoaded(url: url)
                return player
            }
        )

        try playback.loadAudioFile(at: firstURL)
        playback.togglePlayback()

        try playback.loadAudioFile(at: secondURL)

        #expect(firstPlayer.stopCallCount == 1)
        #expect(secondPlayer.loadedURL == secondURL)
        #expect(playback.state == .ready)
    }

    @Test
    func loadErrorLeavesPlaybackUnavailableForTheView() throws {
        let fileManager = FileManager.default
        let missingURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("missing.wav")
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                let player = NativeAudioPlayerSpy()
                player.markLoaded(url: url)
                return player
            }
        )

        try playback.loadAudioFile(at: missingURL)

        #expect(playback.isPlaybackAvailable == false)
        #expect(playback.statusText == "Recording file is missing.")
        #expect(playback.duration == 0)
        #expect(playback.currentTime == 0)
    }

    @Test
    func loadReadyFilePublishesDuration() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        let nativePlayer = NativeAudioPlayerSpy()
        nativePlayer.duration = 95
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                nativePlayer.markLoaded(url: url)
                return nativePlayer
            }
        )

        try playback.loadAudioFile(at: audioURL)

        #expect(playback.duration == 95)
        #expect(playback.currentTime == 0)
    }

    @Test
    func playbackCompletionResetsStateAndTime() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        let nativePlayer = NativeAudioPlayerSpy()
        nativePlayer.duration = 120
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                nativePlayer.markLoaded(url: url)
                return nativePlayer
            }
        )

        try playback.loadAudioFile(at: audioURL)
        playback.seek(to: 37)
        playback.togglePlayback()

        nativePlayer.finishPlayback()

        #expect(playback.state == .ready)
        #expect(playback.currentTime == 0)
    }

    @Test
    func seekUpdatesNativePlayerTimeAndPublishedProgress() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let audioURL = rootURL.appendingPathComponent("audio.wav")
        fileManager.createFile(atPath: audioURL.path, contents: Data("stub".utf8))

        let nativePlayer = NativeAudioPlayerSpy()
        nativePlayer.duration = 120
        let playback = MeetingAudioPlayback(
            fileManager: fileManager,
            nativePlayerFactory: { url in
                nativePlayer.markLoaded(url: url)
                return nativePlayer
            }
        )

        try playback.loadAudioFile(at: audioURL)
        playback.seek(to: 84)

        #expect(nativePlayer.currentTime == 84)
        #expect(playback.currentTime == 84)
    }

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
            waveformExtractor: { _ in nil }
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
}
