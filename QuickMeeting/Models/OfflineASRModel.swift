import Foundation

/// Stable app-owned identifiers. UI, persistence, and alignment never depend
/// on concrete ASR-library model enums.
nonisolated enum OfflineASRModelID: String, Codable, CaseIterable, Sendable {
    case parakeetTDTv3 = "parakeet-tdt-v3"
    case gigaAMMultilingualLargeCTC = "gigaam-multilingual-large-ctc"
    case qwen3ASR17B = "qwen3-asr-1.7b"
}

nonisolated enum OfflineJobSchedule: String, Codable, CaseIterable, Sendable {
    case serial
    case concurrent
}

nonisolated enum GigaAMMultilingualVariant: String, Codable, CaseIterable, Sendable {
    case ssl = "multilingual_ssl"
    case largeSSL = "multilingual_large_ssl"
    case ctc = "multilingual_ctc"
    case largeCTC = "multilingual_large_ctc"
}

nonisolated struct ASRBackendSnapshot: Codable, Equatable, Sendable {
    var backendID: String
    var modelID: OfflineASRModelID
    var modelName: String
    var modelVersion: String
    var runtime: String
    var configuration: [String: String]
}

nonisolated enum OfflineASRModelAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

nonisolated struct OfflineASRModelDescriptor: Identifiable, Equatable, Sendable {
    var id: OfflineASRModelID
    var displayName: String
    var exactVariant: String
    var availability: OfflineASRModelAvailability
}

nonisolated enum OfflineASRModelCatalog {
    /// Candidate catalog is intentionally broader than the selector. A model is
    /// selectable only after a real in-process backend exists and is smoke-tested.
    static let candidates: [OfflineASRModelDescriptor] = [
        OfflineASRModelDescriptor(
            id: .parakeetTDTv3,
            displayName: "FluidAudio Parakeet TDT v3",
            exactVariant: "FluidInference/parakeet-tdt-0.6b-v3-coreml (int8 encoder)",
            availability: .available
        ),
        OfflineASRModelDescriptor(
            id: .gigaAMMultilingualLargeCTC,
            displayName: "GigaAM Multilingual Large",
            exactVariant: "multilingual_large_ctc",
            availability: .unavailable(
                reason: "The official GigaAM release supplies PyTorch/ONNX runtimes, but no ship-ready native Swift/CoreML runtime with its word-timestamp alignment path."
            )
        ),
        OfflineASRModelDescriptor(
            id: .qwen3ASR17B,
            displayName: "Qwen3-ASR 1.7B",
            exactVariant: "Qwen/Qwen3-ASR-1.7B + Qwen3-ForcedAligner-0.6B",
            availability: .unavailable(
                reason: "The official runtime is Python-first; the pinned FluidAudio build does not expose a production Qwen3 ASR backend, and an audited Swift forced-alignment adapter is not installed."
            )
        ),
    ]

    static var selectable: [OfflineASRModelDescriptor] {
        candidates.filter { $0.availability.isAvailable }
    }

    static func descriptor(for id: OfflineASRModelID) -> OfflineASRModelDescriptor? {
        candidates.first { $0.id == id }
    }
}
