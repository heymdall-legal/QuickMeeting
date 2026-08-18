//
//  MeetingScreenObservationCaptureService.swift
//  QuickMeeting
//

import Foundation

nonisolated protocol ScreenObservationSinking: Sendable {
    func saveObservation(_ observation: ScreenObservation) async throws
}

nonisolated protocol ScreenSnapshotRecording: Sendable {
    func capture(
        meetingID: UUID,
        meetingFolderURL: URL,
        startedAt: Date,
        sequenceNumber: Int
    ) async throws -> ScreenObservation?
}

@MainActor
protocol MeetingScreenObservationCapturing: AnyObject {
    func start(meetingID: UUID, meetingFolderURL: URL, startedAt: Date) async
    func stop() async
}

@MainActor
final class MeetingScreenObservationCaptureController: MeetingScreenObservationCapturing {
    private let service: MeetingScreenObservationCaptureService

    init(service: MeetingScreenObservationCaptureService) {
        self.service = service
    }

    func start(meetingID: UUID, meetingFolderURL: URL, startedAt: Date) async {
        await service.start(
            meetingID: meetingID,
            meetingFolderURL: meetingFolderURL,
            startedAt: startedAt
        )
    }

    func stop() async {
        await service.stop()
    }
}

actor MeetingScreenObservationCaptureService {
    private let recorder: any ScreenSnapshotRecording
    private let observationSink: any ScreenObservationSinking
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    init(
        recorder: any ScreenSnapshotRecording,
        observationSink: any ScreenObservationSinking,
        interval: TimeInterval = 2
    ) {
        self.recorder = recorder
        self.observationSink = observationSink
        self.interval = interval
    }

    func start(meetingID: UUID, meetingFolderURL: URL, startedAt: Date) async {
        task?.cancel()

        let recorder = recorder
        let observationSink = observationSink
        let interval = interval

        func capture(sequenceNumber: Int) async {
            do {
                if let observation = try await recorder.capture(
                    meetingID: meetingID,
                    meetingFolderURL: meetingFolderURL,
                    startedAt: startedAt,
                    sequenceNumber: sequenceNumber
                ) {
                    try await observationSink.saveObservation(observation)
                }
            } catch {
                // Screen evidence is best-effort and must never break recording.
            }
        }

        await capture(sequenceNumber: 1)

        guard interval > 0 else {
            task = nil
            return
        }

        task = Task {
            var sequenceNumber = 2
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }

                await capture(sequenceNumber: sequenceNumber)
                sequenceNumber += 1
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

struct ScreenObservationStoreSink: ScreenObservationSinking {
    private let box: MainActorScreenObservationStoreBox

    @MainActor
    init(store: ScreenObservationStore) {
        box = MainActorScreenObservationStoreBox(store: store)
    }

    func saveObservation(_ observation: ScreenObservation) async throws {
        try await box.saveObservation(observation)
    }
}

@MainActor
private final class MainActorScreenObservationStoreBox: @unchecked Sendable {
    private let store: ScreenObservationStore

    init(store: ScreenObservationStore) {
        self.store = store
    }

    func saveObservation(_ observation: ScreenObservation) throws {
        try store.saveObservation(observation)
    }
}
