import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct AutoRecordingSettingsViewModelTests {
    @Test
    func savePersistsUpdatedAutoRecordingSettings() async {
        let store = InMemoryAutoRecordingSettingsStore(settings: .default)
        let viewModel = AutoRecordingSettingsViewModel(settingsStore: store)

        await viewModel.load()
        viewModel.isEnabled = true
        viewModel.stopGracePeriod = 90
        await viewModel.save()

        #expect(store.settings.isEnabled == true)
        #expect(store.settings.stopGracePeriod == 90)
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
