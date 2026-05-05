//
//  RecordingService.swift
//  QuickMeeting
//
//  Created by Codex on 04.05.2026.
//

import Foundation

@MainActor
protocol RecordingService {
    func startRecording(meeting: Meeting, outputURL: URL) async throws
    func stopRecording() async throws
}

enum DefaultRecordingServiceError: LocalizedError, Equatable {
    case recordingAlreadyActive

    var errorDescription: String? {
        switch self {
        case .recordingAlreadyActive:
            "A recording is already active."
        }
    }
}

@MainActor
final class DefaultRecordingService: RecordingService {
    private enum FailureRecoveryState {
        case recording(token: UUID)
    }

    private enum State {
        case idle
        case starting(token: UUID, task: Task<Void, Error>)
        case recording(token: UUID)
        case stopping(token: UUID, task: Task<Void, Error>, failureState: FailureRecoveryState)
    }

    private let audioCapturePipeline: any AudioCapturePipeline
    private var state: State = .idle

    init(audioCapturePipeline: any AudioCapturePipeline) {
        self.audioCapturePipeline = audioCapturePipeline
    }

    func startRecording(meeting _: Meeting, outputURL: URL) async throws {
        guard case .idle = state else {
            throw DefaultRecordingServiceError.recordingAlreadyActive
        }

        let recordingToken = UUID()
        let startTask = Task { @MainActor in
            try await audioCapturePipeline.start(outputURL: outputURL)
        }

        state = .starting(token: recordingToken, task: startTask)

        do {
            try await startTask.value
        } catch {
            reconcileFailedStart(for: recordingToken)
            throw error
        }

        reconcileSuccessfulStart(for: recordingToken)
    }

    func stopRecording() async throws {
        switch state {
        case .idle:
            return
        case .starting(let recordingToken, let startTask):
            let stopTask = Task { @MainActor in
                do {
                    try await startTask.value
                } catch {
                    return
                }

                try await audioCapturePipeline.stop()
            }

            state = .stopping(
                token: recordingToken,
                task: stopTask,
                failureState: .recording(token: recordingToken)
            )

            try await awaitStopTask(
                stopTask,
                for: recordingToken,
                failureState: .recording(token: recordingToken)
            )
        case .recording(let recordingToken):
            let stopTask = Task { @MainActor in
                try await audioCapturePipeline.stop()
            }

            state = .stopping(
                token: recordingToken,
                task: stopTask,
                failureState: .recording(token: recordingToken)
            )

            try await awaitStopTask(
                stopTask,
                for: recordingToken,
                failureState: .recording(token: recordingToken)
            )
        case .stopping(let recordingToken, let stopTask, let failureState):
            try await awaitStopTask(
                stopTask,
                for: recordingToken,
                failureState: failureState
            )
        }
    }

    private func awaitStopTask(
        _ stopTask: Task<Void, Error>,
        for recordingToken: UUID,
        failureState: FailureRecoveryState
    ) async throws {
        do {
            try await stopTask.value
            reconcileCompletedStop(for: recordingToken)
        } catch {
            reconcileFailedStop(for: recordingToken, failureState: failureState)
            throw error
        }
    }

    private func reconcileFailedStart(for recordingToken: UUID) {
        switch state {
        case .starting(let currentToken, _) where currentToken == recordingToken:
            state = .idle
        case .stopping(let currentToken, _, _) where currentToken == recordingToken:
            state = .idle
        default:
            break
        }
    }

    private func reconcileSuccessfulStart(for recordingToken: UUID) {
        guard case .starting(let currentToken, _) = state,
              currentToken == recordingToken else {
            return
        }

        state = .recording(token: recordingToken)
    }

    private func reconcileCompletedStop(for recordingToken: UUID) {
        guard case .stopping(let currentToken, _, _) = state,
              currentToken == recordingToken else {
            return
        }

        state = .idle
    }

    private func reconcileFailedStop(
        for recordingToken: UUID,
        failureState: FailureRecoveryState
    ) {
        guard case .stopping(let currentToken, _, _) = state,
              currentToken == recordingToken else {
            return
        }

        state = materializedState(for: failureState)
    }

    private func materializedState(for failureState: FailureRecoveryState) -> State {
        switch failureState {
        case .recording(let recordingToken):
            .recording(token: recordingToken)
        }
    }
}
