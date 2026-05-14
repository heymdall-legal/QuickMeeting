//
//  AutoRecordingSettingsStore.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Foundation

protocol AutoRecordingSettingsStoring: Sendable {
    func load() -> AutoRecordingSettings
    func save(_ settings: AutoRecordingSettings)
}

struct AutoRecordingSettingsStore: AutoRecordingSettingsStoring {
    private let userDefaults: UserDefaults
    private let enabledKey = "autoRecording.enabled"
    private let appKey = "autoRecording.app"
    private let startDelayKey = "autoRecording.startDelay"
    private let stopGraceKey = "autoRecording.stopGrace"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AutoRecordingSettings {
        let defaults = AutoRecordingSettings.default
        let selectedApp = AutoRecordingApp(
            rawValue: userDefaults.string(forKey: appKey) ?? ""
        ) ?? defaults.selectedApp

        return AutoRecordingSettings(
            isEnabled: userDefaults.object(forKey: enabledKey) as? Bool ?? defaults.isEnabled,
            selectedApp: selectedApp,
            startDelay: userDefaults.object(forKey: startDelayKey) as? Double ?? defaults.startDelay,
            stopGracePeriod: userDefaults.object(forKey: stopGraceKey) as? Double ?? defaults.stopGracePeriod
        )
    }

    func save(_ settings: AutoRecordingSettings) {
        userDefaults.set(settings.isEnabled, forKey: enabledKey)
        userDefaults.set(settings.selectedApp.rawValue, forKey: appKey)
        userDefaults.set(settings.startDelay, forKey: startDelayKey)
        userDefaults.set(settings.stopGracePeriod, forKey: stopGraceKey)
    }
}
