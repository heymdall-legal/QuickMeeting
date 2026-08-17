import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct OnlineDraftCoordinatorTests {
    @Test
    func unpreparedModelsNeverBlockRecordingStop() async throws {
        let harness = try OnlineDraftCoordinatorHarness()
        let coordinator = harness.makeCoordinator(
            asrBackend: CoordinatorASRBackend(),
            stopTimeout: 0.02
        )

        coordinator.start(meetingID: harness.meeting.id)
        let started = ContinuousClock.now
        await coordinator.stop()

        #expect(coordinator.modelState == .notPrepared)
        #expect(started.duration(to: .now) < .milliseconds(100))
        #expect(harness.meeting.transcriptLifecycleState == nil)
    }

    @Test
    func flushDeadlineReturnsControlWhenStreamingBackendDoesNotFinish() async throws {
        let harness = try OnlineDraftCoordinatorHarness()
        let coordinator = harness.makeCoordinator(
            asrBackend: HangingFinishASRBackend(),
            stopTimeout: 0.02
        )
        await coordinator.prepareModels()
        #expect(coordinator.modelState == .ready)
        coordinator.start(meetingID: harness.meeting.id)
        _ = harness.channel.offer(TimestampedAudioChunk(
            startTime: 0,
            sampleRate: 16_000,
            samples: [Float](repeating: 0.1, count: 16_000)
        ))

        let started = ContinuousClock.now
        await coordinator.stop()

        #expect(started.duration(to: .now) < .seconds(1))
        #expect(harness.meeting.transcriptLifecycleState == .draftAvailable)
    }
}

@MainActor
private final class OnlineDraftCoordinatorHarness {
    let container: ModelContainer
    let meeting: Meeting
    let store: MeetingStore
    let channel = BoundedOnlineAudioChannel()

    init() throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        store = MeetingStore(modelContext: container.mainContext)
        let folder = URL(fileURLWithPath: "/tmp/online-draft-\(UUID().uuidString)")
        meeting = try store.createMeeting(
            title: "Online draft",
            startedAt: Date(),
            folderURL: folder,
            audioFileURL: folder.appendingPathComponent("audio.m4a")
        )
    }

    func makeCoordinator(
        asrBackend: any StreamingASRBackend,
        stopTimeout: TimeInterval
    ) -> OnlineDraftCoordinator {
        OnlineDraftCoordinator(
            meetingStore: store,
            channel: channel,
            pipeline: OnlineDraftPipeline(
                asrBackend: asrBackend,
                diarizationBackend: CoordinatorDiarizationBackend()
            ),
            stopTimeout: stopTimeout
        )
    }
}

private actor CoordinatorASRBackend: StreamingASRBackend {
    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        progress(1, "ready")
    }
    func beginSession(languageCode: String) async throws {}
    func process(samples16k: [Float]) async throws -> String { "тест" }
    func finishSession() async throws -> String { "тест" }
}

private actor HangingFinishASRBackend: StreamingASRBackend {
    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        progress(1, "ready")
    }
    func beginSession(languageCode: String) async throws {}
    func process(samples16k: [Float]) async throws -> String { "тест" }
    func finishSession() async throws -> String {
        try await Task.sleep(for: .seconds(10))
        return "тест"
    }
}

private actor CoordinatorDiarizationBackend: StreamingDiarizationBackend {
    func prepare(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        progress(1, "ready")
    }
    func beginSession() async throws {}
    func process(samples16k: [Float]) async throws -> [SpeakerInterval] { [] }
    func finishSession() async throws -> [SpeakerInterval] { [] }
}
