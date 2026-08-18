import Foundation

nonisolated struct TimestampedAudioChunk: Equatable, Sendable {
    var startTime: TimeInterval
    var sampleRate: Double
    var samples: [Float]

    var endTime: TimeInterval {
        startTime + Double(samples.count) / sampleRate
    }
}

nonisolated protocol OnlineAudioChunkSink: Sendable {
    /// Receives the system-audio timeline only. Microphone-only regions are
    /// represented by silence so draft timestamps stay aligned to the recording.
    /// Must return immediately. `false` means the draft branch dropped an update;
    /// it never indicates loss in the authoritative file writer.
    @discardableResult
    func offer(_ chunk: TimestampedAudioChunk) -> Bool
}

final class BoundedOnlineAudioChannel: OnlineAudioChunkSink, @unchecked Sendable {
    struct Metrics: Equatable, Sendable {
        var acceptedBuffers: Int
        var droppedBuffers: Int
    }

    private let lock = NSLock()
    private var continuation: AsyncStream<TimestampedAudioChunk>.Continuation?
    private var acceptedBuffers = 0
    private var droppedBuffers = 0

    func beginSession(capacity: Int = 24) -> AsyncStream<TimestampedAudioChunk> {
        lock.withLock {
            continuation?.finish()
            acceptedBuffers = 0
            droppedBuffers = 0
            var createdContinuation: AsyncStream<TimestampedAudioChunk>.Continuation?
            let stream = AsyncStream<TimestampedAudioChunk>(
                bufferingPolicy: .bufferingNewest(max(1, capacity))
            ) { continuation in
                createdContinuation = continuation
            }
            continuation = createdContinuation
            return stream
        }
    }

    @discardableResult
    func offer(_ chunk: TimestampedAudioChunk) -> Bool {
        lock.withLock {
            guard let continuation else { return false }
            switch continuation.yield(chunk) {
            case .enqueued:
                acceptedBuffers += 1
                return true
            case .dropped:
                droppedBuffers += 1
                return false
            case .terminated:
                return false
            @unknown default:
                return false
            }
        }
    }

    func finishSession() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }

    func metrics() -> Metrics {
        lock.withLock {
            Metrics(acceptedBuffers: acceptedBuffers, droppedBuffers: droppedBuffers)
        }
    }
}
