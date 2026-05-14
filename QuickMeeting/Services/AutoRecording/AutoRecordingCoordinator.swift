//
//  AutoRecordingCoordinator.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Foundation

@MainActor
protocol AutoRecordingIntentSink: AnyObject {
    func requestAutoRecordingStart() async
    func requestAutoRecordingStop() async
}

protocol AutoRecordingScheduledTask {
    func cancel()
}

protocol AutoRecordingClock: Sendable {
    func schedule(
        after seconds: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any AutoRecordingScheduledTask
}

struct TaskSleepAutoRecordingClock: AutoRecordingClock {
    func schedule(
        after seconds: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any AutoRecordingScheduledTask {
        let task = Task {
            let duration = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else {
                return
            }

            await operation()
        }

        return AutoRecordingTaskHandle {
            task.cancel()
        }
    }
}

@MainActor
final class AutoRecordingCoordinator {
    private let clock: any AutoRecordingClock
    private weak var intentSink: (any AutoRecordingIntentSink)?
    private let startDelay: TimeInterval
    private let stopGracePeriod: TimeInterval
    private var isRecording = false
    private var pendingStartTask: (any AutoRecordingScheduledTask)?
    private var pendingStopTask: (any AutoRecordingScheduledTask)?

    init(
        clock: any AutoRecordingClock = TaskSleepAutoRecordingClock(),
        intentSink: any AutoRecordingIntentSink,
        startDelay: TimeInterval,
        stopGracePeriod: TimeInterval
    ) {
        self.clock = clock
        self.intentSink = intentSink
        self.startDelay = startDelay
        self.stopGracePeriod = stopGracePeriod
    }

    func handle(_ presence: MeetingAppPresence) async {
        switch presence {
        case .candidateActive, .activeMeeting:
            pendingStopTask?.cancel()
            pendingStopTask = nil

            guard !isRecording, pendingStartTask == nil else {
                return
            }

            pendingStartTask = clock.schedule(after: startDelay) { [weak intentSink] in
                await intentSink?.requestAutoRecordingStart()
            }

        case .inactive, .ending:
            pendingStartTask?.cancel()
            pendingStartTask = nil

            guard isRecording, pendingStopTask == nil else {
                return
            }

            pendingStopTask = clock.schedule(after: stopGracePeriod) { [weak intentSink] in
                await intentSink?.requestAutoRecordingStop()
            }
        }
    }

    func recordingDidStart() {
        isRecording = true
        pendingStartTask?.cancel()
        pendingStartTask = nil
    }

    func recordingDidStop() {
        isRecording = false
        pendingStopTask?.cancel()
        pendingStopTask = nil
    }
}

private struct AutoRecordingTaskHandle: AutoRecordingScheduledTask {
    private let cancelOperation: @Sendable () -> Void

    init(cancelOperation: @escaping @Sendable () -> Void) {
        self.cancelOperation = cancelOperation
    }

    func cancel() {
        cancelOperation()
    }
}
