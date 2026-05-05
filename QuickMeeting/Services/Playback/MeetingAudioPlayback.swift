import AVFAudio
import Combine
import Foundation

enum MeetingAudioPlaybackState: Equatable {
    case idle
    case ready
    case playing
    case paused
    case failed(message: String)
}

protocol NativeAudioPlaying: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var onFinishPlayback: (@MainActor () -> Void)? { get set }
    func play()
    func pause()
    func stop()
    func prepareToPlay()
}

@MainActor
final class MeetingAudioPlayback: ObservableObject {
    @Published private(set) var state: MeetingAudioPlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private let fileManager: FileManager
    private let nativePlayerFactory: @MainActor (URL) throws -> NativeAudioPlaying
    private var nativePlayer: NativeAudioPlaying?
    private var progressTimer: Timer?

    init(
        fileManager: FileManager = .default,
        nativePlayerFactory: @escaping @MainActor (URL) throws -> NativeAudioPlaying = { url in
            try AVAudioPlayerAdapter(contentsOf: url)
        }
    ) {
        self.fileManager = fileManager
        self.nativePlayerFactory = nativePlayerFactory
    }

    var isPlaybackAvailable: Bool {
        switch state {
        case .ready, .playing, .paused:
            return true
        case .idle, .failed:
            return false
        }
    }

    var statusText: String {
        switch state {
        case .idle:
            return "Preparing recording..."
        case .ready:
            return "Ready"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .failed(let message):
            return message
        }
    }

    var elapsedTimeText: String {
        formatTime(currentTime)
    }

    var durationText: String {
        formatTime(duration)
    }

    func loadAudioFile(at fileURL: URL) throws {
        stopProgressUpdates()
        nativePlayer?.stop()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            nativePlayer = nil
            duration = 0
            currentTime = 0
            state = .failed(message: "Recording file is missing.")
            return
        }

        let player = try nativePlayerFactory(fileURL)
        player.onFinishPlayback = { [weak self] in
            self?.handlePlaybackFinished()
        }
        player.prepareToPlay()
        nativePlayer = player
        duration = player.duration
        currentTime = player.currentTime
        state = .ready
    }

    func togglePlayback() {
        guard let nativePlayer else {
            return
        }

        switch state {
        case .ready, .paused:
            nativePlayer.play()
            startProgressUpdates()
            state = .playing
        case .playing:
            nativePlayer.pause()
            refreshProgress()
            stopProgressUpdates()
            state = .paused
        case .idle, .failed:
            return
        }
    }

    func seek(to time: TimeInterval) {
        guard let nativePlayer else {
            return
        }

        let clampedTime = min(max(time, 0), duration)
        nativePlayer.currentTime = clampedTime
        currentTime = clampedTime
    }

    private func startProgressUpdates() {
        stopProgressUpdates()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshProgress()
            }
        }
    }

    private func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func refreshProgress() {
        guard let nativePlayer else {
            return
        }

        currentTime = min(nativePlayer.currentTime, duration)
    }

    private func handlePlaybackFinished() {
        stopProgressUpdates()
        nativePlayer?.currentTime = 0
        currentTime = 0
        state = .ready
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

final class AVAudioPlayerAdapter: NSObject, NativeAudioPlaying, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onFinishPlayback: (@MainActor () -> Void)?

    init(contentsOf url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
    }

    var duration: TimeInterval {
        player.duration
    }

    var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.stop()
        player.currentTime = 0
    }

    func prepareToPlay() {
        player.prepareToPlay()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            onFinishPlayback?()
        }
    }
}
