import Darwin
import Foundation

/// Polls the process resident footprint while a transcription job is active.
/// Sampling makes this a job-scoped peak instead of the process lifetime peak
/// reported by rusage, which would be misleading on warm runs.
nonisolated final class TranscriptionMemoryPeakTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var peakBytes: UInt64
    private var samplingTask: Task<Void, Never>?

    init(sampleIntervalNanoseconds: UInt64 = 100_000_000) {
        peakBytes = Self.currentResidentBytes()
        samplingTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(nanoseconds: sampleIntervalNanoseconds)
            }
        }
    }

    func stop() -> UInt64 {
        samplingTask?.cancel()
        samplingTask = nil
        sample()
        return lock.withLock { peakBytes }
    }

    deinit {
        samplingTask?.cancel()
    }

    private func sample() {
        let residentBytes = Self.currentResidentBytes()
        lock.withLock {
            peakBytes = max(peakBytes, residentBytes)
        }
    }

    private static func currentResidentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }
}
