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
    private let appsKey = "autoRecording.apps"
    private let legacyAppKey = "autoRecording.app"
    private let startDelayKey = "autoRecording.startDelay"
    private let stopGraceKey = "autoRecording.stopGrace"
    private let maximumMeetingDurationKey = "autoRecording.maximumMeetingDurationHours"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> AutoRecordingSettings {
        let defaults = AutoRecordingSettings.default
        let selectedApps = loadSelectedApps()

        return AutoRecordingSettings(
            isEnabled: userDefaults.object(forKey: enabledKey) as? Bool ?? defaults.isEnabled,
            selectedApps: selectedApps,
            startDelay: userDefaults.object(forKey: startDelayKey) as? Double ?? defaults.startDelay,
            stopGracePeriod: userDefaults.object(forKey: stopGraceKey) as? Double ?? defaults.stopGracePeriod,
            maximumMeetingDurationHours: userDefaults.object(forKey: maximumMeetingDurationKey) == nil
                ? defaults.maximumMeetingDurationHours
                : userDefaults.integer(forKey: maximumMeetingDurationKey)
        )
    }

    func save(_ settings: AutoRecordingSettings) {
        userDefaults.set(settings.isEnabled, forKey: enabledKey)
        userDefaults.set(encode(uniqueTargets(from: settings.selectedApps)), forKey: appsKey)
        userDefaults.removeObject(forKey: legacyAppKey)
        userDefaults.set(settings.startDelay, forKey: startDelayKey)
        userDefaults.set(settings.stopGracePeriod, forKey: stopGraceKey)
        userDefaults.set(settings.maximumMeetingDurationHours, forKey: maximumMeetingDurationKey)
    }

    private func loadSelectedApps() -> [AutoRecordingTarget] {
        if let data = userDefaults.data(forKey: appsKey),
           let decoded = try? JSONDecoder().decode([AutoRecordingTarget].self, from: data) {
            return uniqueTargets(from: decoded)
        }

        guard let legacy = userDefaults.string(forKey: legacyAppKey),
              legacy == AutoRecordingApp.tolk.rawValue else {
            return []
        }

        return [.legacyTolk]
    }

    private func uniqueTargets(from targets: [AutoRecordingTarget]) -> [AutoRecordingTarget] {
        var seen = Set<String>()
        return targets.filter { seen.insert($0.bundleIdentifier).inserted }
    }

    private func encode(_ targets: [AutoRecordingTarget]) -> Data? {
        try? JSONEncoder().encode(targets)
    }
}
