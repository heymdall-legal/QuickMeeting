import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct MeetingAppMonitorTests {
    @Test
    func anyWatchedAppCanDrivePresenceActive() async {
        let settingsStore = TestAutoRecordingSettingsStore(
            settings: AutoRecordingSettings(
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
                startDelay: 10,
                stopGracePeriod: 60
            )
        )
        let activitySource = StubMeetingAppActivitySource(samplesByBundleIdentifier: [
            "us.zoom.xos": MeetingAppActivitySample(
                bundleIdentifier: "us.zoom.xos",
                isRunning: false,
                isFrontmost: false,
                hadRecentFocus: false,
                hasVisibleWindow: false,
                isMicrophoneActive: false
            ),
            "com.microsoft.teams2": MeetingAppActivitySample(
                bundleIdentifier: "com.microsoft.teams2",
                isRunning: true,
                isFrontmost: false,
                hadRecentFocus: true,
                hasVisibleWindow: false,
                isMicrophoneActive: true
            )
        ])
        let presenceSink = PresenceSinkSpy()
        let monitor = MeetingAppMonitor(
            settingsStore: settingsStore,
            activitySource: activitySource,
            presenceSink: presenceSink
        )

        await monitor.pollOnceForTesting()

        #expect(presenceSink.presences == [.candidateActive])
    }

    @Test
    func emptyWatchedAppListReportsInactive() async {
        let settingsStore = TestAutoRecordingSettingsStore(
            settings: AutoRecordingSettings(
                isEnabled: true,
                selectedApps: [],
                startDelay: 10,
                stopGracePeriod: 60
            )
        )
        let presenceSink = PresenceSinkSpy()
        let subject = MeetingAppMonitor(
            settingsStore: settingsStore,
            activitySource: StubMeetingAppActivitySource(samplesByBundleIdentifier: [:]),
            presenceSink: presenceSink
        )

        await subject.pollOnceForTesting()

        #expect(presenceSink.presences == [.inactive])
    }
}

private struct TestAutoRecordingSettingsStore: AutoRecordingSettingsStoring {
    let settings: AutoRecordingSettings

    func load() -> AutoRecordingSettings {
        settings
    }

    func save(_ settings: AutoRecordingSettings) {
        _ = settings
    }
}

private struct StubMeetingAppActivitySource: MeetingAppActivitySource {
    let samplesByBundleIdentifier: [String: MeetingAppActivitySample]

    func sample(forBundleIdentifier bundleIdentifier: String) -> MeetingAppActivitySample {
        samplesByBundleIdentifier[bundleIdentifier] ?? MeetingAppActivitySample(
            bundleIdentifier: bundleIdentifier,
            isRunning: false,
            isFrontmost: false,
            hadRecentFocus: false,
            hasVisibleWindow: false,
            isMicrophoneActive: false
        )
    }
}

@MainActor
private final class PresenceSinkSpy: AutoRecordingPresenceUpdating {
    private(set) var presences: [MeetingAppPresence] = []
    var canStopRecording: Bool = false

    func updateAutoRecordingPresence(_ presence: MeetingAppPresence) async {
        presences.append(presence)
    }
}
