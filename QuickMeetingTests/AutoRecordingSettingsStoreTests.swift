import Foundation
import Testing
@testable import QuickMeeting

struct AutoRecordingSettingsStoreTests {
    @Test
    func settingsRoundTripWithMultipleTargets() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = AutoRecordingSettingsStore(userDefaults: defaults)

        #expect(store.load().isEnabled == false)
        #expect(store.load().selectedApps.isEmpty)
        #expect(store.load().startDelay == 10)
        #expect(store.load().stopGracePeriod == 60)
        #expect(store.load().maximumMeetingDurationHours == 3)

        let updated = AutoRecordingSettings(
            isEnabled: true,
            selectedApps: [
                AutoRecordingTarget(
                    bundleIdentifier: "us.zoom.xos",
                    displayName: "zoom.us",
                    appPath: "/Applications/zoom.us.app"
                ),
                AutoRecordingTarget(
                    bundleIdentifier: "com.microsoft.teams2",
                    displayName: "Microsoft Teams",
                    appPath: "/Applications/Microsoft Teams.app"
                )
            ],
            startDelay: 12,
            stopGracePeriod: 75,
            maximumMeetingDurationHours: 5
        )
        store.save(updated)

        #expect(store.load() == updated)
    }

    @Test
    func legacySelectedAppMigratesToWatchedList() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("tolk", forKey: "autoRecording.app")
        let store = AutoRecordingSettingsStore(userDefaults: defaults)

        let migrated = store.load()
        #expect(
            migrated.selectedApps == [
                AutoRecordingTarget(
                    bundleIdentifier: "kontur.talk",
                    displayName: "Толк",
                    appPath: ""
                )
            ]
        )
    }
}
