//
//  RecordingDeadlineClock.swift
//  QuickMeeting
//

import Foundation

@MainActor
protocol RecordingDeadlineClock: Sendable {
    func schedule(
        after seconds: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any RecordingDeadlineScheduledTask
}

protocol RecordingDeadlineScheduledTask {
    func cancel()
}

@MainActor
struct TaskSleepRecordingDeadlineClock: RecordingDeadlineClock {
    func schedule(
        after seconds: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any RecordingDeadlineScheduledTask {
        let task = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }
            await operation()
        }
        return RecordingDeadlineTaskHandle { task.cancel() }
    }
}

private struct RecordingDeadlineTaskHandle: RecordingDeadlineScheduledTask {
    let cancellation: @Sendable () -> Void

    func cancel() {
        cancellation()
    }
}
