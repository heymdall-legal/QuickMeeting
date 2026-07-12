import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct MeetingScreenObservationCaptureServiceTests {
    @Test
    func startCapturesInitialObservationAndPersistsIt() async throws {
        let meetingID = UUID()
        let recorder = StubScreenSnapshotRecorder(
            observations: [
                ScreenObservation(
                    meetingID: meetingID,
                    capturedAtOffset: 0,
                    imageRelativePath: "screen-observations/0001.jpg",
                    thumbnailRelativePath: nil
                )
            ]
        )
        let store = InMemoryScreenObservationSink()
        let service = MeetingScreenObservationCaptureService(
            recorder: recorder,
            observationSink: store,
            interval: 60
        )

        await service.start(
            meetingID: meetingID,
            meetingFolderURL: URL(fileURLWithPath: "/tmp/meeting"),
            startedAt: Date(timeIntervalSince1970: 100)
        )
        await service.stop()

        #expect(await recorder.captureCount == 1)
        #expect(await store.saved.map(\.meetingID) == [meetingID])
    }

    @Test
    func stopWithoutStartIsNoop() async {
        let service = MeetingScreenObservationCaptureService(
            recorder: StubScreenSnapshotRecorder(observations: []),
            observationSink: InMemoryScreenObservationSink(),
            interval: 60
        )

        await service.stop()
    }
}

private actor InMemoryScreenObservationSink: ScreenObservationSinking {
    private(set) var saved = [ScreenObservation]()

    func saveObservation(_ observation: ScreenObservation) async throws {
        saved.append(observation)
    }
}

private actor StubScreenSnapshotRecorder: ScreenSnapshotRecording {
    private let observations: [ScreenObservation]
    private(set) var captureCount = 0

    init(observations: [ScreenObservation]) {
        self.observations = observations
    }

    func capture(
        meetingID: UUID,
        meetingFolderURL: URL,
        startedAt: Date,
        sequenceNumber: Int
    ) async throws -> ScreenObservation? {
        captureCount += 1
        return observations.dropFirst(sequenceNumber - 1).first
    }
}
