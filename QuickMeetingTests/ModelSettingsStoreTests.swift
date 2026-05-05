import Foundation
import Testing
@testable import QuickMeeting

struct ModelSettingsStoreTests {
    @Test
    func defaultModelRoundTripsStoredValue() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = ModelSettingsStore(userDefaults: defaults)

        #expect(store.defaultModelID == nil)

        store.defaultModelID = .small

        #expect(store.defaultModelID == .small)
    }

    @Test
    func unsupportedStoredValueIsIgnored() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("unsupported-model", forKey: "defaultTranscriptionModelID")
        let store = ModelSettingsStore(userDefaults: defaults)

        #expect(store.defaultModelID == nil)
    }
}
