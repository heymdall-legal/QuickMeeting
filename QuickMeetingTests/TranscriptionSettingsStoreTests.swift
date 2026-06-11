import Foundation
import Testing
@testable import QuickMeeting

struct TranscriptionSettingsStoreTests {
    @Test
    func loadDefaultsToNoneLanguageAndEmptyPrompt() {
        let suiteName = "TranscriptionSettingsStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = TranscriptionSettingsStore(userDefaults: defaults)

        #expect(store.load() == .default)
    }

    @Test
    func savePersistsLanguageAndPrompt() {
        let suiteName = "TranscriptionSettingsStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = TranscriptionSettingsStore(userDefaults: defaults)
        let settings = TranscriptionSettings(
            language: .russian,
            initialPrompt: "Alice, Bob, Kubernetes"
        )

        store.save(settings)

        #expect(store.load() == settings)
    }
}
