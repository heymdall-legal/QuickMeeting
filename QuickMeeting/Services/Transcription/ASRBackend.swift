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
    var modelID: OfflineASRModelID
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
    var backendSnapshot: ASRBackendSnapshot
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

nonisolated protocol ASRModelPreparing: Sendable {
    func prepare(
        modelID: OfflineASRModelID,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws
}

enum ASRBackendRouterError: LocalizedError, Equatable {
    case unavailable(OfflineASRModelID)

    var errorDescription: String? {
        switch self {
        case .unavailable(let modelID):
            return OfflineASRModelCatalog.descriptor(for: modelID).map {
                "\($0.displayName) is not available: \(unavailableReason($0.availability))"
            } ?? "The selected offline ASR backend is unavailable."
        }
    }

    private func unavailableReason(_ availability: OfflineASRModelAvailability) -> String {
        switch availability {
        case .available: return "backend is not registered"
        case .unavailable(let reason): return reason
        }
    }
}

actor ASRBackendRouter: ASRBackend, ASRModelPreparing {
    private let backends: [OfflineASRModelID: any ASRBackend]

    init(backends: [OfflineASRModelID: any ASRBackend]) {
        self.backends = backends
    }

    func transcribe(
        _ request: ASRBackendRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ASRBackendOutput {
        guard let backend = backends[request.modelID] else {
            throw ASRBackendRouterError.unavailable(request.modelID)
        }
        return try await backend.transcribe(request, progress: progress)
    }

    func prepare(
        modelID: OfflineASRModelID,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        guard let backend = backends[modelID] else {
            throw ASRBackendRouterError.unavailable(modelID)
        }
        guard let preparing = backend as? any ASRModelPreparing else {
            progress(1, "Ready")
            return
        }
        try await preparing.prepare(modelID: modelID, progress: progress)
    }
}
