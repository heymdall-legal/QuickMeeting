//
//  MeetingAppMonitor.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Foundation

@MainActor
final class MeetingAppMonitor {
    private let settingsStore: any AutoRecordingSettingsStoring
    private let activitySource: any MeetingAppActivitySource
    private let appViewModel: AppViewModel
    private let pollInterval: TimeInterval
    private var detector = MeetingPresenceDetector()
    private var task: Task<Void, Never>?
    private var lastSelectedApp: AutoRecordingApp?

    init(
        settingsStore: any AutoRecordingSettingsStoring,
        activitySource: any MeetingAppActivitySource,
        appViewModel: AppViewModel,
        pollInterval: TimeInterval = 1
    ) {
        self.settingsStore = settingsStore
        self.activitySource = activitySource
        self.appViewModel = appViewModel
        self.pollInterval = pollInterval
    }

    func start() {
        guard task == nil else {
            return
        }

        task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                await self.pollOnce()

                let duration = UInt64(self.pollInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: duration)
            }
        }
    }

    private func pollOnce() async {
        let settings = settingsStore.load()

        guard settings.isEnabled else {
            detector = MeetingPresenceDetector()
            lastSelectedApp = nil
            await appViewModel.updateAutoRecordingPresence(.inactive)
            return
        }

        if lastSelectedApp != settings.selectedApp {
            detector = MeetingPresenceDetector()
            lastSelectedApp = settings.selectedApp
        }

        let sample = activitySource.sample(for: settings.selectedApp)
        let detectedPresence = detector.evaluate(sample)
        let presentationPresence: MeetingAppPresence

        if detectedPresence == .inactive, appViewModel.canStopRecording {
            presentationPresence = .ending
        } else {
            presentationPresence = detectedPresence
        }

        await appViewModel.updateAutoRecordingPresence(presentationPresence)
    }
}
