import Foundation
import Testing
@testable import QuickMeeting

struct CalendarSettingsStoreTests {
    @Test
    func selectedCalendarIdentifiersRoundTrip() {
        let suiteName = "CalendarSettingsStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = CalendarSettingsStore(userDefaults: defaults)

        #expect(store.selectedCalendarIDs() == [])

        store.saveSelectedCalendarIDs(["work", "personal"])

        #expect(store.selectedCalendarIDs() == ["work", "personal"])
    }
}
