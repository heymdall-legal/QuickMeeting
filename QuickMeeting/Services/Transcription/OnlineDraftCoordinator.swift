import Foundation

@MainActor
final class OnlineDraftCoordinator {
    private let meetingStore: MeetingStore
    private let channel: BoundedOnlineAudioChannel
    private let pipeline: OnlineDraftPipeline
    private var meetingID: UUID?
    private var processingTask: Task<OnlineDraftTelemetry, Error>?

    init(
        meetingStore: MeetingStore,
        channel: BoundedOnlineAudioChannel,
        pipeline: OnlineDraftPipeline
    ) {
        self.meetingStore = meetingStore
        self.channel = channel
        self.pipeline = pipeline
    }

    func prepareModels() async {
        try? await pipeline.prepare(progress: { _, _ in })
    }

    func start(meetingID: UUID) {
        guard processingTask == nil else { return }
        self.meetingID = meetingID
        try? meetingStore.beginOnlineDraft(meetingID: meetingID, updatedAt: Date())
        let stream = channel.beginSession(capacity: 256)
        let pipeline = pipeline
        processingTask = Task { [self] in
            try await pipeline.run(stream: stream) { event in
                try? self.meetingStore.upsertOnlineDraftEvent(
                    meetingID: meetingID,
                    event: event,
                    updatedAt: Date()
                )
            }
        }
    }

    func stop() async {
        guard let meetingID else { return }
        channel.finishSession()
        var telemetry: OnlineDraftTelemetry
        do {
            telemetry = try await processingTask?.value ?? OnlineDraftTelemetry()
        } catch {
            telemetry = OnlineDraftTelemetry(failureStage: error.localizedDescription)
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
        processingTask = nil
        self.meetingID = nil
    }
}
