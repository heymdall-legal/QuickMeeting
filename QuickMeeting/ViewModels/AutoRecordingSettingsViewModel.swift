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
    @Published var selectedApps: [AutoRecordingTarget] = []
    @Published var selectedApp: AutoRecordingApp = .tolk
    @Published var startDelay: Double = 10
    @Published var stopGracePeriod: Double = 60
    @Published var maximumMeetingDurationHours = 3
    @Published private(set) var errorMessage: String?

    private let settingsStore: any AutoRecordingSettingsStoring
    private let metadataReader: any AppBundleMetadataReading

    init(
        settingsStore: any AutoRecordingSettingsStoring,
        metadataReader: any AppBundleMetadataReading = NativeAppBundleMetadataReader()
    ) {
        self.settingsStore = settingsStore
        self.metadataReader = metadataReader
    }

    func load() async {
        let settings = settingsStore.load()
        isEnabled = settings.isEnabled
        selectedApps = settings.selectedApps
        selectedApp = settings.selectedApp
        startDelay = settings.startDelay
        stopGracePeriod = settings.stopGracePeriod
        maximumMeetingDurationHours = settings.maximumMeetingDurationHours
        errorMessage = nil
    }

    func save() async {
        settingsStore.save(
            AutoRecordingSettings(
                isEnabled: isEnabled,
                selectedApps: selectedApps,
                startDelay: startDelay,
                stopGracePeriod: stopGracePeriod,
                maximumMeetingDurationHours: maximumMeetingDurationHours
            )
        )
    }

    func addSelectedApp(at url: URL) async throws {
        do {
            let metadata = try metadataReader.readMetadata(at: url)
            guard !selectedApps.contains(where: { $0.bundleIdentifier == metadata.bundleIdentifier }) else {
                errorMessage = nil
                return
            }

            selectedApps.append(
                AutoRecordingTarget(
                    bundleIdentifier: metadata.bundleIdentifier,
                    displayName: metadata.displayName,
                    appPath: metadata.appPath
                )
            )
            selectedApp = selectedApps.first?.legacyApp ?? selectedApp
            errorMessage = nil
            await save()
        } catch let error as AppBundleMetadataReaderError {
            errorMessage = error.localizedDescription
        }
    }

    func removeSelectedApp(bundleIdentifier: String) async {
        selectedApps.removeAll { $0.bundleIdentifier == bundleIdentifier }
        selectedApp = selectedApps.first?.legacyApp ?? .tolk
        errorMessage = nil
        await save()
    }

    func clearError() {
        errorMessage = nil
    }
}
