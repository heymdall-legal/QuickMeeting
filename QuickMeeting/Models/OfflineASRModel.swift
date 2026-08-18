import Foundation

/// Stable app-owned identifiers. UI, persistence, and alignment never depend
/// on concrete ASR-library model enums.
nonisolated enum OfflineASRModelID: String, Codable, CaseIterable, Sendable {
    case parakeetTDTv3 = "parakeet-tdt-v3"
    case gigaAMV3 = "gigaam-v3-e2e-rnnt"
    case qwen3ASR17B = "qwen3-asr-1.7b"
}

nonisolated enum OfflineJobSchedule: String, Codable, CaseIterable, Sendable {
    case serial
    case concurrent
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
    /// Models available to the offline finalization pipeline. Native model
    /// weights are kept in the app's Application Support container.
    static let candidates: [OfflineASRModelDescriptor] = [
        OfflineASRModelDescriptor(
            id: .parakeetTDTv3,
            displayName: "FluidAudio Parakeet TDT v3",
            exactVariant: "FluidInference/parakeet-tdt-0.6b-v3-coreml (int8 encoder)",
            availability: .available
        ),
        OfflineASRModelDescriptor(
            id: .qwen3ASR17B,
            displayName: "Qwen3-ASR 1.7B + ForcedAligner",
            exactVariant: "aufklarer/Qwen3-ASR-1.7B-MLX-5bit + Qwen3-ForcedAligner-0.6B-8bit",
            availability: .available
        ),
        OfflineASRModelDescriptor(
            id: .gigaAMV3,
            displayName: "GigaAM v3 · e2e_rnnt",
            exactVariant: "handy-computer/gigaam-v3-e2e-rnnt-gguf · e2e_rnnt · Q8_0",
            availability: .available
        ),
    ]

    static var selectable: [OfflineASRModelDescriptor] {
        candidates.filter { $0.availability.isAvailable }
    }

    static func descriptor(for id: OfflineASRModelID) -> OfflineASRModelDescriptor? {
        candidates.first { $0.id == id }
    }
}
