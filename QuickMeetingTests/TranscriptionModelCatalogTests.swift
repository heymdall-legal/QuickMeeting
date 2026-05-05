import Testing
@testable import QuickMeeting

struct TranscriptionModelCatalogTests {
    @Test
    func supportedModelsArePinnedAndSorted() {
        let models = TranscriptionModelCatalog.supportedModels

        #expect(models.map(\.id) == [.tiny, .small, .largeV3])
        #expect(models.map(\.argmaxModelID) == [
            "tiny",
            "small",
            "large-v3-v20240930_626MB",
        ])
        #expect(models.map(\.displayName) == [
            "Tiny",
            "Small",
            "Large v3",
        ])
    }
}
