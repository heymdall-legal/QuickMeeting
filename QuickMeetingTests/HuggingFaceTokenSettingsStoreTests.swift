import Foundation
import Testing
@testable import QuickMeeting

struct HuggingFaceTokenSettingsStoreTests {
    @Test
    func loadDefaultsToEmptyToken() {
        let suiteName = "HuggingFaceTokenSettingsStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = HuggingFaceTokenSettingsStore(userDefaults: defaults)

        #expect(store.loadToken().isEmpty)
    }

    @Test
    func savePersistsTokenVerbatim() {
        let suiteName = "HuggingFaceTokenSettingsStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = HuggingFaceTokenSettingsStore(userDefaults: defaults)

        store.saveToken("hf_example_token")

        #expect(store.loadToken() == "hf_example_token")
    }
}
