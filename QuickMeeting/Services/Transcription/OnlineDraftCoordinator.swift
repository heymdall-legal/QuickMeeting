import Combine
import Foundation
import OSLog

@MainActor
protocol OnlineDraftCoordinating: AnyObject {
    func start(meetingID: UUID)
    func stop() async
}

nonisolated enum OnlineDraftModelState: Equatable, Sendable {
    case notPrepared
    case preparing(progress: Double, phase: String)
    case ready
    case failed(message: String)
}

@MainActor
final class OnlineDraftCoordinator: OnlineDraftCoordinating, ObservableObject {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuickMeeting",
        category: "OnlineDraft"
    )

    private let meetingStore: MeetingStore
    private let channel: BoundedOnlineAudioChannel
    private let pipeline: OnlineDraftPipeline
    private let stopTimeout: TimeInterval
    @Published private(set) var modelState: OnlineDraftModelState = .notPrepared
    private var meetingID: UUID?
    private var sessionToken: UUID?
    private var processingTask: Task<OnlineDraftTelemetry, Error>?

    init(
        meetingStore: MeetingStore,
        channel: BoundedOnlineAudioChannel,
        pipeline: OnlineDraftPipeline,
        stopTimeout: TimeInterval = 8
    ) {
        self.meetingStore = meetingStore
        self.channel = channel
        self.pipeline = pipeline
        self.stopTimeout = stopTimeout
    }

    func prepareModels() async {
        switch modelState {
        case .ready, .preparing:
            return
        case .notPrepared, .failed:
            break
        }

        modelState = .preparing(progress: 0, phase: "Preparing online models")
        let startedAt = ProcessInfo.processInfo.systemUptime
        Self.logger.info("Online model preparation started")
        do {
            try await pipeline.prepare { progress, phase in
                Self.logger.debug(
                    "Online model preparation phase=\(phase, privacy: .public) progress=\(progress)"
                )
                Task { @MainActor [self] in
                    guard case .preparing = self.modelState else { return }
                    self.modelState = .preparing(
                        progress: min(max(progress, 0), 1),
                        phase: phase
                    )
                }
            }
            modelState = .ready
            Self.logger.info(
                "Online models ready durationSeconds=\(ProcessInfo.processInfo.systemUptime - startedAt)"
            )
        } catch {
            modelState = .failed(message: error.localizedDescription)
            Self.logger.error(
                "Online model preparation failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func start(meetingID: UUID) {
        guard processingTask == nil else {
            Self.logger.error("Online draft start ignored because another session is active")
            return
        }
        guard modelState == .ready else {
            Self.logger.notice(
                "Online draft skipped because models are not ready; authoritative recording continues"
            )
            return
        }

        let sessionToken = UUID()
        self.meetingID = meetingID
        self.sessionToken = sessionToken
        try? meetingStore.beginOnlineDraft(meetingID: meetingID, updatedAt: Date())
        let stream = channel.beginSession(capacity: 256)
        let pipeline = pipeline
        Self.logger.info("Online draft session started")
        processingTask = Task { [self] in
            try await pipeline.run(stream: stream) { event in
                guard self.sessionToken == sessionToken else { return }
                try? self.meetingStore.upsertOnlineDraftEvent(
                    meetingID: meetingID,
                    event: event,
                    updatedAt: Date()
                )
            }
        }
    }

    func stop() async {
        guard let meetingID, let processingTask else {
            Self.logger.debug("Online draft stop completed without an active session")
            return
        }

        Self.logger.info("Online draft flush started")
        channel.finishSession()
        let outcome = await OnlineDraftStopDeadline.wait(
            for: processingTask,
            timeout: stopTimeout
        )
        var telemetry: OnlineDraftTelemetry
        switch outcome {
        case .completed(.success(let completedTelemetry)):
            telemetry = completedTelemetry
        case .completed(.failure(let error)):
            telemetry = OnlineDraftTelemetry(failureStage: error.localizedDescription)
            Self.logger.error(
                "Online draft flush failed error=\(error.localizedDescription, privacy: .public)"
            )
        case .timedOut:
            sessionToken = nil
            processingTask.cancel()
            telemetry = OnlineDraftTelemetry(
                failureStage: "Online draft flush timed out after \(stopTimeout) seconds"
            )
            Self.logger.error("Online draft flush timed out; recording stop will continue")
        }

        let channelMetrics = channel.metrics()
        telemetry.acceptedBuffers = channelMetrics.acceptedBuffers
        telemetry.droppedBuffers = channelMetrics.droppedBuffers
        try? meetingStore.storeOnlineDraftTelemetry(
            meetingID: meetingID,
            telemetry: telemetry,
            updatedAt: Date()
        )
        try? meetingStore.finishOnlineDraft(meetingID: meetingID, updatedAt: Date())
        Self.logger.info(
            "Online draft session stopped acceptedBuffers=\(channelMetrics.acceptedBuffers) droppedBuffers=\(channelMetrics.droppedBuffers)"
        )
        sessionToken = nil
        self.processingTask = nil
        self.meetingID = nil
    }
}

private enum OnlineDraftStopOutcome: @unchecked Sendable {
    case completed(Result<OnlineDraftTelemetry, Error>)
    case timedOut
}

private enum OnlineDraftStopDeadline {
    static func wait(
        for task: Task<OnlineDraftTelemetry, Error>,
        timeout: TimeInterval
    ) async -> OnlineDraftStopOutcome {
        guard timeout > 0 else { return .timedOut }
        let race = OnlineDraftStopRace()
        let resultObserver = Task {
            await race.complete(.completed(await task.result))
        }
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await race.complete(.timedOut)
        }
        let outcome = await race.value()
        resultObserver.cancel()
        timeoutTask.cancel()
        return outcome
    }
}

private actor OnlineDraftStopRace {
    private var outcome: OnlineDraftStopOutcome?
    private var continuation: CheckedContinuation<OnlineDraftStopOutcome, Never>?

    func value() async -> OnlineDraftStopOutcome {
        if let outcome { return outcome }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(_ outcome: OnlineDraftStopOutcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}
