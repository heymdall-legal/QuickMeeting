import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct RecordingServiceTests {
    @Test
    func captureStopFailureStillStopsBestEffortOnlineDraft() async throws {
        let capture = StopFailingAudioCapturePipeline()
        let onlineDraft = SpyOnlineDraftCoordinator()
        let service = DefaultRecordingService(
            audioCapturePipeline: capture,
            onlineDraftCoordinator: onlineDraft
        )
        let meeting = Meeting(
            title: "Test",
            startedAt: Date(),
            status: .recording,
            audioFilePath: "/tmp/test.m4a"
        )

        try await service.startRecording(
            meeting: meeting,
            outputURL: URL(fileURLWithPath: "/tmp/test.m4a")
        )
        await #expect(throws: RecordingStopTestError.failed) {
            try await service.stopRecording()
        }

        #expect(onlineDraft.startedMeetingIDs == [meeting.id])
        #expect(onlineDraft.stopCount == 1)
    }
}

private enum RecordingStopTestError: Error {
    case failed
}

@MainActor
private final class StopFailingAudioCapturePipeline: AudioCapturePipeline {
    func start(outputURL: URL) async throws {}
    func stop() async throws { throw RecordingStopTestError.failed }
}

@MainActor
private final class SpyOnlineDraftCoordinator: OnlineDraftCoordinating {
    private(set) var startedMeetingIDs: [UUID] = []
    private(set) var stopCount = 0
    func start(meetingID: UUID) { startedMeetingIDs.append(meetingID) }
    func stop() async { stopCount += 1 }
}
