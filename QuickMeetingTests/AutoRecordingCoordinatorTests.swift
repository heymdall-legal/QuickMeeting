import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct AutoRecordingCoordinatorTests {
    @Test
    func startsAfterDelayAndStopsAfterGracePeriod() async {
        let clock = TestAutoRecordingClock()
        let sink = RecordingIntentSinkSpy()
        let coordinator = AutoRecordingCoordinator(
            clock: clock,
            intentSink: sink,
            startDelay: 10,
            stopGracePeriod: 60
        )

        await coordinator.handle(.candidateActive)
        await clock.advance(by: 9)
        #expect(sink.startRequests == 0, "startRequests was \(sink.startRequests)")

        await clock.advance(by: 1)
        #expect(sink.startRequests == 1, "startRequests was \(sink.startRequests)")

        coordinator.recordingDidStart()
        await coordinator.handle(.inactive)
        await clock.advance(by: 59)
        #expect(sink.stopRequests == 0, "stopRequests was \(sink.stopRequests)")

        await clock.advance(by: 1)
        #expect(sink.stopRequests == 1, "stopRequests was \(sink.stopRequests)")
    }

    @Test
    func returningActivityCancelsPendingStop() async {
        let clock = TestAutoRecordingClock()
        let sink = RecordingIntentSinkSpy()
        let coordinator = AutoRecordingCoordinator(
            clock: clock,
            intentSink: sink,
            startDelay: 10,
            stopGracePeriod: 60
        )

        coordinator.recordingDidStart()
        await coordinator.handle(.inactive)
        await clock.advance(by: 30)
        await coordinator.handle(.activeMeeting)
        await clock.advance(by: 40)

        #expect(sink.stopRequests == 0, "stopRequests was \(sink.stopRequests)")
    }
}

@MainActor
private final class TestAutoRecordingClock: AutoRecordingClock {
    private struct ScheduledOperation {
        let target: TimeInterval
        let task: TestScheduledTask
        let operation: @MainActor @Sendable () async -> Void
    }

    private var currentTime: TimeInterval = 0
    private var scheduledOperations: [ScheduledOperation] = []

    func schedule(
        after seconds: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any AutoRecordingScheduledTask {
        let task = TestScheduledTask()
        scheduledOperations.append(
            ScheduledOperation(
                target: currentTime + seconds,
                task: task,
                operation: operation
            )
        )
        return task
    }

    func advance(by interval: TimeInterval) async {
        currentTime += interval
        let ready = scheduledOperations.filter { $0.target <= currentTime }
        scheduledOperations.removeAll { $0.target <= currentTime }

        for scheduledOperation in ready where !scheduledOperation.task.isCancelled {
            await scheduledOperation.operation()
        }
    }
}

@MainActor
private final class RecordingIntentSinkSpy: AutoRecordingIntentSink {
    private(set) var startRequests = 0
    private(set) var stopRequests = 0

    func requestAutoRecordingStart() async {
        startRequests += 1
    }

    func requestAutoRecordingStop() async {
        stopRequests += 1
    }
}

private final class TestScheduledTask: AutoRecordingScheduledTask, @unchecked Sendable {
    private(set) var isCancelled = false

    func cancel() {
        isCancelled = true
    }
}
