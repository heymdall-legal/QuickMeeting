import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct AutoRecordingSettingsViewModelTests {
    @Test
    func addSelectedAppPersistsNewWatchedTarget() async throws {
        let store = InMemoryAutoRecordingSettingsStore(settings: .default)
        let reader = StubAppBundleMetadataReader(
            result: .success(
                AppBundleMetadata(
                    bundleIdentifier: "us.zoom.xos",
                    displayName: "zoom.us",
                    appPath: "/Applications/zoom.us.app"
                )
            )
        )
        let viewModel = AutoRecordingSettingsViewModel(
            settingsStore: store,
            metadataReader: reader
        )

        try await viewModel.addSelectedApp(at: URL(fileURLWithPath: "/Applications/zoom.us.app"))

        #expect(
            store.settings.selectedApps == [
                AutoRecordingTarget(
                    bundleIdentifier: "us.zoom.xos",
                    displayName: "zoom.us",
                    appPath: "/Applications/zoom.us.app"
                )
            ]
        )
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func addSelectedAppIgnoresDuplicateBundleIdentifier() async throws {
        let existing = AutoRecordingTarget(
            bundleIdentifier: "us.zoom.xos",
            displayName: "zoom.us",
            appPath: "/Applications/zoom.us.app"
        )
        let store = InMemoryAutoRecordingSettingsStore(
            settings: AutoRecordingSettings(
                isEnabled: true,
                selectedApps: [existing],
                startDelay: 10,
                stopGracePeriod: 60
            )
        )
        let reader = StubAppBundleMetadataReader(
            result: .success(
                AppBundleMetadata(
                    bundleIdentifier: "us.zoom.xos",
                    displayName: "Zoom Clone",
                    appPath: "/Applications/Zoom Clone.app"
                )
            )
        )
        let viewModel = AutoRecordingSettingsViewModel(
            settingsStore: store,
            metadataReader: reader
        )

        await viewModel.load()
        try await viewModel.addSelectedApp(at: URL(fileURLWithPath: "/Applications/Zoom Clone.app"))

        #expect(store.settings.selectedApps == [existing])
    }

    @Test
    func addSelectedAppStoresValidationError() async throws {
        let store = InMemoryAutoRecordingSettingsStore(settings: .default)
        let reader = StubAppBundleMetadataReader(
            result: .failure(.missingBundleIdentifier)
        )
        let viewModel = AutoRecordingSettingsViewModel(
            settingsStore: store,
            metadataReader: reader
        )

        try await viewModel.addSelectedApp(at: URL(fileURLWithPath: "/Applications/Broken.app"))

        #expect(viewModel.errorMessage == "Selected app has no bundle identifier.")
        #expect(store.settings.selectedApps.isEmpty)
    }

    @Test
    func removeSelectedAppPersistsUpdatedWatchedList() async {
        let zoom = AutoRecordingTarget(
            bundleIdentifier: "us.zoom.xos",
            displayName: "zoom.us",
            appPath: "/Applications/zoom.us.app"
        )
        let teams = AutoRecordingTarget(
            bundleIdentifier: "com.microsoft.teams2",
            displayName: "Microsoft Teams",
            appPath: "/Applications/Microsoft Teams.app"
        )
        let store = InMemoryAutoRecordingSettingsStore(
            settings: AutoRecordingSettings(
                isEnabled: true,
                selectedApps: [zoom, teams],
                startDelay: 10,
                stopGracePeriod: 60
            )
        )
        let viewModel = AutoRecordingSettingsViewModel(settingsStore: store)

        await viewModel.load()
        await viewModel.removeSelectedApp(bundleIdentifier: "us.zoom.xos")

        #expect(store.settings.selectedApps == [teams])
    }

    @Test
    func loadExposesPersistedWatchedAppsForSettingsList() async {
        let zoom = AutoRecordingTarget(
            bundleIdentifier: "us.zoom.xos",
            displayName: "zoom.us",
            appPath: "/Applications/zoom.us.app"
        )
        let store = InMemoryAutoRecordingSettingsStore(
            settings: AutoRecordingSettings(
                isEnabled: true,
                selectedApps: [zoom],
                startDelay: 10,
                stopGracePeriod: 60
            )
        )
        let viewModel = AutoRecordingSettingsViewModel(settingsStore: store)

        await viewModel.load()

        #expect(viewModel.selectedApps == [zoom])
    }

    @Test
    func loadAndSaveExposeMaximumMeetingDurationHours() async {
        let store = InMemoryAutoRecordingSettingsStore(
            settings: AutoRecordingSettings(
                isEnabled: false,
                selectedApps: [],
                startDelay: 10,
                stopGracePeriod: 60,
                maximumMeetingDurationHours: 5
            )
        )
        let viewModel = AutoRecordingSettingsViewModel(settingsStore: store)

        await viewModel.load()
        #expect(viewModel.maximumMeetingDurationHours == 5)
        viewModel.maximumMeetingDurationHours = 6
        await viewModel.save()
        #expect(store.settings.maximumMeetingDurationHours == 6)
    }
}

private final class InMemoryAutoRecordingSettingsStore: AutoRecordingSettingsStoring, @unchecked Sendable {
    var settings: AutoRecordingSettings

    init(settings: AutoRecordingSettings) {
        self.settings = settings
    }

    func load() -> AutoRecordingSettings {
        settings
    }

    func save(_ settings: AutoRecordingSettings) {
        self.settings = settings
    }
}

private struct StubAppBundleMetadataReader: AppBundleMetadataReading {
    let result: Result<AppBundleMetadata, AppBundleMetadataReaderError>

    func readMetadata(at url: URL) throws -> AppBundleMetadata {
        _ = url
        return try result.get()
    }
}
