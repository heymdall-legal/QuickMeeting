import Foundation
import Testing
@testable import QuickMeeting

struct OfflineASRBenchmarkRunnerTests {
    @Test
    func reportsComparableMetricsAndExplicitlySkipsUnavailableBackends() async throws {
        let runner = OfflineASRBenchmarkRunner(backends: [
            .parakeetTDTv3: BenchmarkASRBackend(),
        ])
        let rows = await runner.run(cases: [
            OfflineASRBenchmarkCase(
                id: "ru-1",
                samples16k: [Float](repeating: 0, count: 16_000),
                referenceText: "Привет мир 42",
                importantTerms: ["мир", "42"]
            )
        ])

        #expect(rows.count == 3)
        let completed = try #require(rows.first { $0.modelID == .parakeetTDTv3 })
        #expect(completed.status == .completed)
        #expect(completed.wordErrorRate == 0)
        #expect(completed.characterErrorRate == 0)
        #expect(completed.importantTermRecall == 1)
        #expect(completed.timestampCoverage == 1)
        #expect(completed.realtimeFactor != nil)
        #expect(rows.filter { if case .skipped = $0.status { true } else { false } }.count == 2)
    }
}

private struct BenchmarkASRBackend: ASRBackend {
    func transcribe(
        _ request: ASRBackendRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ASRBackendOutput {
        progress(1)
        return ASRBackendOutput(
            transcript: TimedTranscript(text: "Привет мир 42", words: [
                TimedWord(text: "Привет", startTime: 0, endTime: 0.2, confidence: 1),
                TimedWord(text: "мир", startTime: 0.2, endTime: 0.4, confidence: 1),
                TimedWord(text: "42", startTime: 0.4, endTime: 0.6, confidence: 1),
            ]),
            adjustedText: nil,
            replacements: [],
            modelName: "test",
            backendSnapshot: ParakeetASRBackend.backendSnapshot,
            resolvedCTCMode: nil,
            warnings: [],
            wasColdStart: false,
            modelLoadingSeconds: 0,
            asrWallSeconds: 0,
            ctcWallSeconds: 0,
            nativeProcessingSeconds: 0
        )
    }
}
