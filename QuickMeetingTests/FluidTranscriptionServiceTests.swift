import FluidAudio
import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

// MARK: - Service behaviour

@MainActor
struct FluidTranscriptionServiceTests {
    @Test
    func transcribePersistsTranscriptAndCompletesMeeting() async throws {
        let harness = try FluidTranscriptionHarness(
            outcome: .success(
                FluidTranscriptionResult(
                    speakers: [TranscriptSpeaker(id: "S1", displayName: "Speaker 1")],
                    segments: [TranscriptSegment(text: "Hello", startTime: 0, endTime: 1.5, speakerID: "S1")]
                )
            )
        )
        let meeting = try harness.createRecordedMeeting()

        try await harness.service.transcribe(meetingID: meeting.id)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .completed)
        #expect(reloaded.transcriptPreview == "Hello")
        #expect(reloaded.transcriptSpeakers.map(\.displayName) == ["Speaker 1"])
        #expect(reloaded.transcriptSegments.map(\.speakerID) == ["S1"])
        #expect(harness.progressCenter.progress(for: meeting.id) == nil)
        #expect(harness.progressCenter.diarizationProgress(for: meeting.id) == nil)
    }

    @Test
    func transcribeForwardsKnownSpeakerSnapshotsAndThresholdToPipeline() async throws {
        let harness = try FluidTranscriptionHarness(
            outcome: .success(.empty),
            similarityThreshold: 0.73
        )
        let meeting = try harness.createRecordedMeeting()
        try harness.knownSpeakerStore.findOrCreateSpeaker(named: "Alice", now: .now)
        try harness.knownSpeakerStore.appendCentroid(
            [0.5, 0.25],
            to: try harness.firstKnownSpeakerID(),
            sourceMeetingID: nil,
            sourceSpeakerID: nil,
            now: .now
        )

        try await harness.service.transcribe(meetingID: meeting.id)

        let received = harness.pipeline.receivedKnownSpeakers
        #expect(received.count == 1)
        let snapshot = try #require(received.first)
        #expect(snapshot.displayName == "Alice")
        #expect(snapshot.centroids == [[0.5, 0.25]])
        #expect(harness.pipeline.receivedThreshold == 0.73)
    }

    @Test
    func transcribeForwardsConfiguredLanguageToPipeline() async throws {
        let harness = try FluidTranscriptionHarness(outcome: .success(.empty), languageCode: "de")
        let meeting = try harness.createRecordedMeeting()

        try await harness.service.transcribe(meetingID: meeting.id)

        #expect(harness.pipeline.receivedLanguageCode == "de")
    }

    @Test
    func transcribeForwardsNilLanguageForAutoDetect() async throws {
        let harness = try FluidTranscriptionHarness(outcome: .success(.empty), languageCode: nil)
        let meeting = try harness.createRecordedMeeting()

        try await harness.service.transcribe(meetingID: meeting.id)

        #expect(harness.pipeline.receivedLanguageCode == nil)
    }

    @Test
    func transcribeOmitsKnownSpeakersWithoutCentroids() async throws {
        let harness = try FluidTranscriptionHarness(outcome: .success(.empty))
        let meeting = try harness.createRecordedMeeting()
        // A known speaker exists, but has no enrolled centroids yet.
        try harness.knownSpeakerStore.findOrCreateSpeaker(named: "Bob", now: .now)

        try await harness.service.transcribe(meetingID: meeting.id)

        #expect(harness.pipeline.receivedKnownSpeakers.isEmpty)
    }

    @Test
    func transcribeEnrollsBankMatchedSpeakers() async throws {
        let harness = try FluidTranscriptionHarness(
            outcome: .success(
                FluidTranscriptionResult(
                    speakers: [
                        TranscriptSpeaker(
                            id: "S1",
                            displayName: "Alice",
                            labelSource: .bankMatched,
                            matchedKnownSpeakerID: "known-alice",
                            centroid: [0.1, 0.2]
                        ),
                        TranscriptSpeaker(id: "S2", displayName: "Speaker 2"),
                    ],
                    segments: [TranscriptSegment(text: "Hi", startTime: 0, endTime: 1, speakerID: "S1")]
                )
            )
        )
        let meeting = try harness.createRecordedMeeting()

        try await harness.service.transcribe(meetingID: meeting.id)

        let calls = harness.enrollmentService.calls
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        #expect(call.displayName == "Alice")
        #expect(call.speaker.id == "S1")
        #expect(call.meetingID == meeting.id)
    }

    @Test
    func transcribePersistsTranscriptEvenWhenEnrollmentFails() async throws {
        let harness = try FluidTranscriptionHarness(
            outcome: .success(
                FluidTranscriptionResult(
                    speakers: [
                        TranscriptSpeaker(
                            id: "S1",
                            displayName: "Alice",
                            labelSource: .bankMatched,
                            matchedKnownSpeakerID: "known-alice",
                            centroid: [0.1, 0.2]
                        )
                    ],
                    segments: [TranscriptSegment(text: "Hi", startTime: 0, endTime: 1, speakerID: "S1")]
                )
            ),
            enrollmentResult: .failure(FluidTestError.boom)
        )
        let meeting = try harness.createRecordedMeeting()

        try await harness.service.transcribe(meetingID: meeting.id)

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .completed)
        #expect(harness.enrollmentService.calls.count == 1)
    }

    @Test
    func transcribeMapsGenericPipelineErrorAndMarksMeetingFailed() async throws {
        let harness = try FluidTranscriptionHarness(
            outcome: .failure(NSError(domain: "Fluid", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"]))
        )
        let meeting = try harness.createRecordedMeeting()

        await #expect(throws: FluidTranscriptionServiceError.pipelineFailed("boom")) {
            try await harness.service.transcribe(meetingID: meeting.id)
        }

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .failed)
    }

    @Test
    func transcribePropagatesDomainErrorUnchanged() async throws {
        let harness = try FluidTranscriptionHarness(
            outcome: .failure(FluidTranscriptionServiceError.noAudioDecoded)
        )
        let meeting = try harness.createRecordedMeeting()

        await #expect(throws: FluidTranscriptionServiceError.noAudioDecoded) {
            try await harness.service.transcribe(meetingID: meeting.id)
        }

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .failed)
    }

    @Test
    func transcribeThrowsWhenAudioFileMissingAndLeavesMeetingRecorded() async throws {
        let harness = try FluidTranscriptionHarness(outcome: .success(.empty))
        let meeting = try harness.createRecordedMeeting()
        try harness.fileManager.removeItem(at: URL(fileURLWithPath: meeting.audioFilePath))

        await #expect(throws: TranscriptionServiceError.audioFileMissing) {
            try await harness.service.transcribe(meetingID: meeting.id)
        }

        let reloaded = try harness.reloadMeeting(id: meeting.id)
        #expect(try reloaded.status == .recorded)
    }

    @Test
    func transcribeRejectsSecondJobWhileFirstIsActive() async throws {
        let harness = try FluidTranscriptionHarness(outcome: .success(.empty))
        let firstMeeting = try harness.createRecordedMeeting()
        let secondMeeting = try harness.createRecordedMeeting()
        harness.pipeline.suspendNextRun()

        let task = Task {
            try await harness.service.transcribe(meetingID: firstMeeting.id)
        }
        await harness.pipeline.waitForSuspendedRun()

        await #expect(throws: TranscriptionServiceError.transcriptionAlreadyActive) {
            try await harness.service.transcribe(meetingID: secondMeeting.id)
        }

        harness.pipeline.resume()
        try await task.value
    }
}

// MARK: - Pipeline mapping

@MainActor
struct DefaultFluidAudioPipelineMappingTests {
    @Test
    func orderSpeakersByFirstAppearanceWithGenericLabels() throws {
        let result = DefaultFluidAudioPipeline.makeResult(
            transcriptionResult: makeASRResult(
                text: "hi yo",
                tokens: [
                    token(" hi", start: 0.1, end: 0.4),
                    token(" yo", start: 1.1, end: 1.4),
                ]
            ),
            segments: [
                segment(speaker: "B", embedding: [1, 0], start: 0, end: 1),
                segment(speaker: "A", embedding: [0, 1], start: 1, end: 2),
            ],
            speakerDatabase: nil,
            knownSpeakers: [],
            similarityThreshold: 0.8
        )

        #expect(result.speakers.map(\.id) == ["B", "A"])
        #expect(result.speakers.map(\.displayName) == ["Speaker 1", "Speaker 2"])
        #expect(result.speakers.allSatisfy { $0.labelSource == .generic })
        #expect(result.speakers.allSatisfy { $0.matchedKnownSpeakerID == nil })
    }

    @Test
    func matchKnownSpeakerWhenSimilarityMeetsThreshold() throws {
        let known = FluidKnownSpeakerSnapshot(
            id: "known-alice",
            displayName: "Alice",
            centroids: [[1, 0]]
        )
        let result = DefaultFluidAudioPipeline.makeResult(
            transcriptionResult: makeASRResult(text: "hi", tokens: [token(" hi", start: 0.1, end: 0.4)]),
            segments: [segment(speaker: "S1", embedding: [0, 0], start: 0, end: 1)],
            speakerDatabase: ["S1": [1, 0]],
            knownSpeakers: [known],
            similarityThreshold: 0.8
        )

        let speaker = try #require(result.speakers.first)
        #expect(speaker.displayName == "Alice")
        #expect(speaker.labelSource == .bankMatched)
        #expect(speaker.matchedKnownSpeakerID == "known-alice")
        #expect(speaker.centroid == [1, 0])
    }

    @Test
    func leaveSpeakerGenericWhenSimilarityBelowThreshold() throws {
        let known = FluidKnownSpeakerSnapshot(
            id: "known-alice",
            displayName: "Alice",
            centroids: [[1, 0]]
        )
        let result = DefaultFluidAudioPipeline.makeResult(
            transcriptionResult: makeASRResult(text: "hi", tokens: [token(" hi", start: 0.1, end: 0.4)]),
            segments: [segment(speaker: "S1", embedding: [0, 0], start: 0, end: 1)],
            // Orthogonal to the known centroid -> cosine similarity 0.
            speakerDatabase: ["S1": [0, 1]],
            knownSpeakers: [known],
            similarityThreshold: 0.8
        )

        let speaker = try #require(result.speakers.first)
        #expect(speaker.displayName == "Speaker 1")
        #expect(speaker.labelSource == .generic)
        #expect(speaker.matchedKnownSpeakerID == nil)
    }

    @Test
    func groupTokensIntoSpeakerSegmentsAndJoinSubwords() throws {
        let result = DefaultFluidAudioPipeline.makeResult(
            transcriptionResult: makeASRResult(
                text: "Hello Kostyakov",
                tokens: [
                    token(" Hello", start: 0.10, end: 0.40),
                    token(" Kost", start: 1.10, end: 1.30),
                    token("yakov", start: 1.30, end: 1.50),
                ]
            ),
            segments: [
                segment(speaker: "A", embedding: [1, 0], start: 0, end: 1),
                segment(speaker: "B", embedding: [0, 1], start: 1, end: 3),
            ],
            speakerDatabase: nil,
            knownSpeakers: [],
            similarityThreshold: 0.8
        )

        #expect(result.segments.map(\.text) == ["Hello", "Kostyakov"])
        #expect(result.segments.map(\.speakerID) == ["A", "B"])
        #expect(result.segments.first?.startTime == 0.10)
        #expect(result.segments.last?.endTime == 1.50)
    }

    @Test
    func fallBackToPreviousSpeakerForUnknownGaps() throws {
        let result = DefaultFluidAudioPipeline.makeResult(
            transcriptionResult: makeASRResult(
                text: "Hi there",
                tokens: [
                    token(" Hi", start: 0.20, end: 0.40),
                    // 1.5s falls into a diarization gap -> attributed to the last known speaker.
                    token(" there", start: 1.50, end: 1.80),
                ]
            ),
            segments: [segment(speaker: "A", embedding: [1, 0], start: 0, end: 1)],
            speakerDatabase: nil,
            knownSpeakers: [],
            similarityThreshold: 0.8
        )

        #expect(result.segments.count == 1)
        let only = try #require(result.segments.first)
        #expect(only.text == "Hi there")
        #expect(only.speakerID == "A")
    }

    @Test
    func produceSingleSegmentWhenTokenTimingsMissing() throws {
        let result = DefaultFluidAudioPipeline.makeResult(
            transcriptionResult: makeASRResult(text: "Full text here", tokens: nil),
            segments: [],
            speakerDatabase: nil,
            knownSpeakers: [],
            similarityThreshold: 0.8
        )

        #expect(result.speakers.isEmpty)
        #expect(result.segments.count == 1)
        let only = try #require(result.segments.first)
        #expect(only.text == "Full text here")
        #expect(only.speakerID == nil)
        #expect(only.startTime == nil)
    }

    @Test
    func averageSegmentEmbeddingsWhenNoSpeakerDatabase() throws {
        let result = DefaultFluidAudioPipeline.makeResult(
            transcriptionResult: makeASRResult(text: "a b", tokens: [token(" a", start: 0.1, end: 0.2)]),
            segments: [
                segment(speaker: "S1", embedding: [0, 2], start: 0, end: 1),
                segment(speaker: "S1", embedding: [2, 0], start: 1, end: 2),
            ],
            speakerDatabase: nil,
            knownSpeakers: [],
            similarityThreshold: 0.8
        )

        let speaker = try #require(result.speakers.first)
        #expect(speaker.centroid == [1, 1])
    }

    // MARK: Fixtures

    private func makeASRResult(text: String, tokens: [TokenTiming]?) -> ASRResult {
        ASRResult(
            text: text,
            confidence: 1,
            duration: 2,
            processingTime: 1,
            tokenTimings: tokens
        )
    }

    private func token(_ text: String, start: TimeInterval, end: TimeInterval) -> TokenTiming {
        TokenTiming(token: text, tokenId: 0, startTime: start, endTime: end, confidence: 1)
    }

    private func segment(
        speaker: String,
        embedding: [Float],
        start: Float,
        end: Float
    ) -> TimedSpeakerSegment {
        TimedSpeakerSegment(
            speakerId: speaker,
            embedding: embedding,
            startTimeSeconds: start,
            endTimeSeconds: end,
            qualityScore: 1
        )
    }
}

// MARK: - Test doubles

extension FluidTranscriptionResult {
    fileprivate static let empty = FluidTranscriptionResult(speakers: [], segments: [])
}

@MainActor
private struct FluidTranscriptionHarness {
    let container: ModelContainer
    let context: ModelContext
    let meetingStore: MeetingStore
    let knownSpeakerStore: KnownSpeakerStore
    let progressCenter: TranscriptionProgressCenter
    let fileManager: FileManager
    let meetingFileStore: MeetingFileStore
    let pipeline: StubFluidAudioPipeline
    let enrollmentService: RecordingKnownSpeakerEnrollmentService
    let service: FluidTranscriptionService

    init(
        outcome: StubFluidAudioPipeline.Outcome,
        similarityThreshold: Float = 0.8,
        enrollmentResult: Result<Void, Error> = .success(()),
        languageCode: String? = nil
    ) throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        context = ModelContext(container)
        meetingStore = MeetingStore(modelContext: context)
        knownSpeakerStore = KnownSpeakerStore(modelContext: context)
        progressCenter = TranscriptionProgressCenter()
        fileManager = .default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        meetingFileStore = MeetingFileStore(fileManager: fileManager, rootURL: rootURL)
        pipeline = StubFluidAudioPipeline(outcome: outcome)
        enrollmentService = RecordingKnownSpeakerEnrollmentService(result: enrollmentResult)
        service = FluidTranscriptionService(
            meetingStore: meetingStore,
            progressCenter: progressCenter,
            pipeline: pipeline,
            knownSpeakerStore: knownSpeakerStore,
            knownSpeakerEnrollmentService: enrollmentService,
            languageStore: StubTranscriptionLanguageStore(code: languageCode),
            similarityThreshold: similarityThreshold,
            fileManager: fileManager
        )
    }

    func createRecordedMeeting() throws -> Meeting {
        let startedAt = Date(timeIntervalSince1970: 1_234_567_890)
        let artifacts = try meetingFileStore.createArtifacts(for: UUID(), startedAt: startedAt)
        fileManager.createFile(atPath: artifacts.audioFileURL.path, contents: Data("audio".utf8))
        let meeting = try meetingStore.createMeeting(
            id: UUID(uuidString: artifacts.meetingFolderURL.lastPathComponent) ?? UUID(),
            title: "Design Review",
            startedAt: startedAt,
            folderURL: artifacts.meetingFolderURL,
            audioFileURL: artifacts.audioFileURL
        )
        try meetingStore.finishRecording(meetingID: meeting.id, endedAt: startedAt.addingTimeInterval(60))
        return try reloadMeeting(id: meeting.id)
    }

    func reloadMeeting(id: UUID) throws -> Meeting {
        let verificationContext = ModelContext(container)
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { meeting in
                meeting.id == id
            }
        )
        return try #require(verificationContext.fetch(descriptor).first)
    }

    func firstKnownSpeakerID() throws -> String {
        try #require(knownSpeakerStore.allSpeakers().first?.id)
    }
}

private struct StubTranscriptionLanguageStore: TranscriptionLanguageStoring {
    let code: String?
    func languageCode() -> String? { code }
    func saveLanguageCode(_: String?) {}
}

@MainActor
private final class StubFluidAudioPipeline: FluidAudioTranscribing, @unchecked Sendable {
    enum Outcome {
        case success(FluidTranscriptionResult)
        case failure(Error)
    }

    private var outcome: Outcome
    private(set) var receivedKnownSpeakers: [FluidKnownSpeakerSnapshot] = []
    private(set) var receivedThreshold: Float?
    private(set) var receivedLanguageCode: String?
    private var shouldSuspendNextRun = false
    private var pendingRunCount = 0
    private var pendingContinuation: CheckedContinuation<Void, Never>?

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func suspendNextRun() {
        shouldSuspendNextRun = true
    }

    func waitForSuspendedRun() async {
        while pendingRunCount == 0 {
            await Task.yield()
        }
    }

    func resume() {
        pendingRunCount = max(0, pendingRunCount - 1)
        pendingContinuation?.resume()
        pendingContinuation = nil
    }

    func transcribe(
        audioFileURL _: URL,
        knownSpeakers: [FluidKnownSpeakerSnapshot],
        similarityThreshold: Float,
        languageCode: String?,
        progress _: @escaping @Sendable (FluidTranscriptionProgress) -> Void
    ) async throws -> FluidTranscriptionResult {
        receivedKnownSpeakers = knownSpeakers
        receivedThreshold = similarityThreshold
        receivedLanguageCode = languageCode

        if shouldSuspendNextRun {
            shouldSuspendNextRun = false
            pendingRunCount += 1
            await withCheckedContinuation { continuation in
                pendingContinuation = continuation
            }
        }

        switch outcome {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

@MainActor
private final class RecordingKnownSpeakerEnrollmentService: KnownSpeakerEnrolling, @unchecked Sendable {
    struct Call: Sendable {
        let displayName: String
        let speaker: TranscriptSpeaker
        let meetingID: UUID
    }

    private(set) var calls = [Call]()
    private let result: Result<Void, Error>

    init(result: Result<Void, Error>) {
        self.result = result
    }

    func enroll(displayName: String, speaker: TranscriptSpeaker, meetingID: UUID) async throws {
        calls.append(Call(displayName: displayName, speaker: speaker, meetingID: meetingID))
        try result.get()
    }
}

private enum FluidTestError: Error {
    case boom
}
