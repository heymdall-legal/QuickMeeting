import Foundation
import Testing
@testable import QuickMeeting

struct AutoRecordingSettingsStoreTests {
    @Test
    func settingsRoundTripWithDefaults() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = AutoRecordingSettingsStore(userDefaults: defaults)

        #expect(store.load().isEnabled == false)
        #expect(store.load().selectedApp == .tolk)
        #expect(store.load().startDelay == 10)
        #expect(store.load().stopGracePeriod == 60)

        let updated = AutoRecordingSettings(
            isEnabled: true,
            selectedApp: .tolk,
            startDelay: 12,
            stopGracePeriod: 75
        )
        store.save(updated)

        #expect(store.load() == updated)
    }
}
