//
//  AutoRecordingSettingsViewModel.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Combine
import Foundation

@MainActor
final class AutoRecordingSettingsViewModel: ObservableObject {
    @Published var isEnabled = false
    @Published var selectedApp: AutoRecordingApp = .tolk
    @Published var startDelay: Double = 10
    @Published var stopGracePeriod: Double = 60

    private let settingsStore: any AutoRecordingSettingsStoring

    init(settingsStore: any AutoRecordingSettingsStoring) {
        self.settingsStore = settingsStore
    }

    func load() async {
        let settings = settingsStore.load()
        isEnabled = settings.isEnabled
        selectedApp = settings.selectedApp
        startDelay = settings.startDelay
        stopGracePeriod = settings.stopGracePeriod
    }

    func save() async {
        settingsStore.save(
            AutoRecordingSettings(
                isEnabled: isEnabled,
                selectedApp: selectedApp,
                startDelay: startDelay,
                stopGracePeriod: stopGracePeriod
            )
        )
    }
}
