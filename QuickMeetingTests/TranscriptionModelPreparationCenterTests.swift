import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct TranscriptionModelPreparationCenterTests {
    @Test
    func exposesRealPreparationProgressAndReadyState() async throws {
        let center = TranscriptionModelPreparationCenter(preparer: StubASRModelPreparer())
        #expect(center.state(for: .parakeetTDTv3) == .notPrepared)

        center.prepare(.parakeetTDTv3)
        #expect(center.state(for: .parakeetTDTv3).progress != nil)

        for _ in 0..<20 where center.state(for: .parakeetTDTv3) != .ready {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(center.state(for: .parakeetTDTv3) == .ready)
        #expect(center.state(for: .gigaAMV3) == .notPrepared)
    }
}

private struct StubASRModelPreparer: ASRModelPreparing {
    func prepare(
        modelID: OfflineASRModelID,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        progress(0.5, "Compiling")
        try await Task.sleep(for: .milliseconds(10))
        progress(1, "Ready")
    }
}
