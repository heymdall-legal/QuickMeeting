import Foundation

nonisolated struct TimedWord: Codable, Equatable, Sendable {
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var confidence: Float?
}

nonisolated struct TimedTranscript: Codable, Equatable, Sendable {
    var text: String
    var words: [TimedWord]

    init(text: String, words: [TimedWord] = []) {
        self.text = text
        self.words = words
    }
}

nonisolated struct ASRTextReplacement: Equatable, Sendable {
    var originalText: String
    var replacementText: String
    var shouldReplace: Bool
}

nonisolated struct ASRBackendRequest: Sendable {
    var samples: [Float]
    var languageCode: String?
    var ctcMode: TranscriptionCTCMode
    var glossaryTerms: [TranscriptionGlossaryTerm]
}

nonisolated struct ASRBackendOutput: Sendable {
    var transcript: TimedTranscript
    var adjustedText: String?
    var replacements: [ASRTextReplacement]
    var modelName: String
    var resolvedCTCMode: TranscriptionCTCMode?
    var warnings: [String]
    var wasColdStart: Bool
    var modelLoadingSeconds: TimeInterval
    var asrWallSeconds: TimeInterval
    var ctcWallSeconds: TimeInterval
    var nativeProcessingSeconds: TimeInterval?
}

nonisolated protocol ASRBackend: Sendable {
    func transcribe(
        _ request: ASRBackendRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ASRBackendOutput
}
