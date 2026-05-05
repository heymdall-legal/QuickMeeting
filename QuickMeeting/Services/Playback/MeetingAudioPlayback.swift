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
    func play()
    func pause()
    func stop()
    func prepareToPlay()
}

@MainActor
final class MeetingAudioPlayback: ObservableObject {
    @Published private(set) var state: MeetingAudioPlaybackState = .idle

    private let fileManager: FileManager
    private let nativePlayerFactory: @MainActor (URL) throws -> NativeAudioPlaying
    private var nativePlayer: NativeAudioPlaying?

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

    func loadAudioFile(at fileURL: URL) throws {
        nativePlayer?.stop()

        guard fileManager.fileExists(atPath: fileURL.path) else {
            nativePlayer = nil
            state = .failed(message: "Recording file is missing.")
            return
        }

        let player = try nativePlayerFactory(fileURL)
        player.prepareToPlay()
        nativePlayer = player
        state = .ready
    }

    func togglePlayback() {
        guard let nativePlayer else {
            return
        }

        switch state {
        case .ready, .paused:
            nativePlayer.play()
            state = .playing
        case .playing:
            nativePlayer.pause()
            state = .paused
        case .idle, .failed:
            return
        }
    }
}

final class AVAudioPlayerAdapter: NativeAudioPlaying {
    private let player: AVAudioPlayer

    init(contentsOf url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
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
}
