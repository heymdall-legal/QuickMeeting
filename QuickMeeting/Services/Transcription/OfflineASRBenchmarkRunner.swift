import Darwin
import Foundation

nonisolated struct OfflineASRBenchmarkCase: Sendable {
    var id: String
    var samples16k: [Float]
    var referenceText: String
    var importantTerms: [String]
}

nonisolated enum OfflineASRBenchmarkStatus: Equatable, Sendable {
    case completed
    case skipped(reason: String)
    case failed(message: String)
}

nonisolated struct OfflineASRBenchmarkRow: Equatable, Sendable {
    var modelID: OfflineASRModelID
    var caseID: String
    var status: OfflineASRBenchmarkStatus
    var wordErrorRate: Double?
    var characterErrorRate: Double?
    var importantTermRecall: Double?
    var timestampCoverage: Double?
    var wallSeconds: TimeInterval?
    var realtimeFactor: Double?
    var peakMemoryBytes: UInt64?
    var backendSnapshot: ASRBackendSnapshot?
}

/// Produces one neutral table and deliberately never selects a winner.
actor OfflineASRBenchmarkRunner {
    private let backends: [OfflineASRModelID: any ASRBackend]

    init(backends: [OfflineASRModelID: any ASRBackend]) {
        self.backends = backends
    }

    func run(
        cases: [OfflineASRBenchmarkCase],
        modelIDs: [OfflineASRModelID] = OfflineASRModelID.allCases
    ) async -> [OfflineASRBenchmarkRow] {
        var rows: [OfflineASRBenchmarkRow] = []
        for modelID in modelIDs {
            guard let backend = backends[modelID] else {
                let reason = Self.unavailableReason(modelID)
                rows.append(contentsOf: cases.map {
                    Self.emptyRow(modelID: modelID, caseID: $0.id, status: .skipped(reason: reason))
                })
                continue
            }
            for benchmarkCase in cases {
                let started = ProcessInfo.processInfo.systemUptime
                do {
                    let output = try await backend.transcribe(
                        ASRBackendRequest(
                            modelID: modelID,
                            samples: benchmarkCase.samples16k,
                            languageCode: "ru-RU",
                            ctcMode: .off,
                            glossaryTerms: []
                        ),
                        progress: { _ in }
                    )
                    let wall = ProcessInfo.processInfo.systemUptime - started
                    let audioDuration = Double(benchmarkCase.samples16k.count) / 16_000
                    rows.append(OfflineASRBenchmarkRow(
                        modelID: modelID,
                        caseID: benchmarkCase.id,
                        status: .completed,
                        wordErrorRate: Self.errorRate(
                            reference: Self.words(benchmarkCase.referenceText),
                            hypothesis: Self.words(output.transcript.text)
                        ),
                        characterErrorRate: Self.errorRate(
                            reference: Array(Self.normalized(benchmarkCase.referenceText)),
                            hypothesis: Array(Self.normalized(output.transcript.text))
                        ),
                        importantTermRecall: Self.termRecall(
                            terms: benchmarkCase.importantTerms,
                            hypothesis: output.transcript.text
                        ),
                        timestampCoverage: Self.timestampCoverage(output.transcript),
                        wallSeconds: wall,
                        realtimeFactor: audioDuration > 0 ? wall / audioDuration : nil,
                        peakMemoryBytes: Self.peakMemoryBytes(),
                        backendSnapshot: output.backendSnapshot
                    ))
                } catch {
                    rows.append(Self.emptyRow(
                        modelID: modelID,
                        caseID: benchmarkCase.id,
                        status: .failed(message: error.localizedDescription)
                    ))
                }
            }
        }
        return rows
    }

    private static func unavailableReason(_ modelID: OfflineASRModelID) -> String {
        guard let descriptor = OfflineASRModelCatalog.descriptor(for: modelID) else {
            return "Backend is not registered."
        }
        if case .unavailable(let reason) = descriptor.availability { return reason }
        return "Backend is not registered."
    }

    private static func emptyRow(
        modelID: OfflineASRModelID,
        caseID: String,
        status: OfflineASRBenchmarkStatus
    ) -> OfflineASRBenchmarkRow {
        OfflineASRBenchmarkRow(
            modelID: modelID,
            caseID: caseID,
            status: status,
            wordErrorRate: nil,
            characterErrorRate: nil,
            importantTermRecall: nil,
            timestampCoverage: nil,
            wallSeconds: nil,
            realtimeFactor: nil,
            peakMemoryBytes: nil,
            backendSnapshot: nil
        )
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .reduce(into: "") { $0.append($1) }
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func words(_ text: String) -> [String] {
        normalized(text).split(separator: " ").map(String.init)
    }

    private static func errorRate<T: Equatable>(reference: [T], hypothesis: [T]) -> Double {
        guard !reference.isEmpty else { return hypothesis.isEmpty ? 0 : 1 }
        var previous = Array(0...hypothesis.count)
        for (referenceIndex, expected) in reference.enumerated() {
            var current = [referenceIndex + 1] + Array(repeating: 0, count: hypothesis.count)
            for (hypothesisIndex, actual) in hypothesis.enumerated() {
                current[hypothesisIndex + 1] = min(
                    current[hypothesisIndex] + 1,
                    previous[hypothesisIndex + 1] + 1,
                    previous[hypothesisIndex] + (expected == actual ? 0 : 1)
                )
            }
            previous = current
        }
        return Double(previous[hypothesis.count]) / Double(reference.count)
    }

    private static func termRecall(terms: [String], hypothesis: String) -> Double? {
        let normalizedTerms = terms.map(normalized).filter { !$0.isEmpty }
        guard !normalizedTerms.isEmpty else { return nil }
        let normalizedHypothesis = normalized(hypothesis)
        let hits = normalizedTerms.filter { normalizedHypothesis.contains($0) }.count
        return Double(hits) / Double(normalizedTerms.count)
    }

    private static func timestampCoverage(_ transcript: TimedTranscript) -> Double? {
        let transcriptWords = words(transcript.text)
        guard !transcriptWords.isEmpty else { return nil }
        let valid = transcript.words.filter {
            $0.startTime.isFinite && $0.endTime.isFinite && $0.endTime >= $0.startTime
        }.count
        return Double(valid) / Double(transcriptWords.count)
    }

    private static func peakMemoryBytes() -> UInt64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return UInt64(max(0, usage.ru_maxrss))
    }
}
