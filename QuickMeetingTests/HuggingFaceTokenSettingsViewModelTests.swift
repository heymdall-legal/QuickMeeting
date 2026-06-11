import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct HuggingFaceTokenSettingsViewModelTests {
    @Test
    func loadExposesPersistedToken() async {
        let store = InMemoryHuggingFaceTokenSettingsStore(token: "hf_saved_token")
        let viewModel = HuggingFaceTokenSettingsViewModel(settingsStore: store)

        await viewModel.load()

        #expect(viewModel.token == "hf_saved_token")
        #expect(viewModel.hasToken)
    }

    @Test
    func savePersistsCurrentToken() async {
        let store = InMemoryHuggingFaceTokenSettingsStore(token: "")
        let viewModel = HuggingFaceTokenSettingsViewModel(settingsStore: store)
        viewModel.token = "hf_new_token"

        await viewModel.save()

        #expect(store.token == "hf_new_token")
    }

    @Test
    func hasTokenTrimsWhitespaceOnlyInput() {
        let store = InMemoryHuggingFaceTokenSettingsStore(token: "")
        let viewModel = HuggingFaceTokenSettingsViewModel(settingsStore: store)
        viewModel.token = "   "

        #expect(!viewModel.hasToken)
    }
}

private final class InMemoryHuggingFaceTokenSettingsStore: HuggingFaceTokenSettingsStoring, @unchecked Sendable {
    var token: String

    init(token: String) {
        self.token = token
    }

    func loadToken() -> String {
        token
    }

    func saveToken(_ token: String) {
        self.token = token
    }
}
