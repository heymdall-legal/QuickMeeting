import Combine
import Foundation

@MainActor
final class HuggingFaceTokenSettingsViewModel: ObservableObject {
    @Published var token: String

    private let settingsStore: any HuggingFaceTokenSettingsStoring

    init(settingsStore: any HuggingFaceTokenSettingsStoring) {
        self.settingsStore = settingsStore
        token = settingsStore.loadToken()
    }

    var hasToken: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() async {
        token = settingsStore.loadToken()
    }

    func save() async {
        settingsStore.saveToken(token)
    }
}
