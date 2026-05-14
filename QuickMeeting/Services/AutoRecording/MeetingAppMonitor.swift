//
//  MeetingAppMonitor.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Foundation

@MainActor
protocol AutoRecordingPresenceUpdating: AnyObject {
    var canStopRecording: Bool { get }
    func updateAutoRecordingPresence(_ presence: MeetingAppPresence) async
}

@MainActor
final class MeetingAppMonitor {
    private let settingsStore: any AutoRecordingSettingsStoring
    private let activitySource: any MeetingAppActivitySource
    private weak var presenceSink: (any AutoRecordingPresenceUpdating)?
    private let pollInterval: TimeInterval
    private var detector = MeetingPresenceDetector()
    private var task: Task<Void, Never>?
    private var lastSelectedBundleIdentifiers: [String] = []

    init(
        settingsStore: any AutoRecordingSettingsStoring,
        activitySource: any MeetingAppActivitySource,
        presenceSink: any AutoRecordingPresenceUpdating,
        pollInterval: TimeInterval = 1
    ) {
        self.settingsStore = settingsStore
        self.activitySource = activitySource
        self.presenceSink = presenceSink
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

    func pollOnceForTesting() async {
        await pollOnce()
    }

    private func pollOnce() async {
        let settings = settingsStore.load()

        guard settings.isEnabled else {
            detector = MeetingPresenceDetector()
            lastSelectedBundleIdentifiers = []
            await presenceSink?.updateAutoRecordingPresence(.inactive)
            return
        }

        let bundleIdentifiers = settings.selectedApps.map(\.bundleIdentifier)
        guard !bundleIdentifiers.isEmpty else {
            detector = MeetingPresenceDetector()
            lastSelectedBundleIdentifiers = []
            await presenceSink?.updateAutoRecordingPresence(.inactive)
            return
        }

        if lastSelectedBundleIdentifiers != bundleIdentifiers {
            detector = MeetingPresenceDetector()
            lastSelectedBundleIdentifiers = bundleIdentifiers
        }

        let samples = bundleIdentifiers.map {
            activitySource.sample(forBundleIdentifier: $0)
        }

        if let qualifyingSample = samples.first(where: {
            $0.isMicrophoneActive && $0.isRunning && ($0.hasVisibleWindow || $0.hadRecentFocus)
        }) {
            let detectedPresence = detector.evaluate(qualifyingSample)
            await presenceSink?.updateAutoRecordingPresence(detectedPresence)
            return
        }

        guard let fallbackSample = samples.first else {
            await presenceSink?.updateAutoRecordingPresence(.inactive)
            return
        }

        let detectedPresence = detector.evaluate(fallbackSample)
        let presentationPresence: MeetingAppPresence

        if detectedPresence == .inactive, presenceSink?.canStopRecording == true {
            presentationPresence = .ending
        } else {
            presentationPresence = detectedPresence
        }

        await presenceSink?.updateAutoRecordingPresence(presentationPresence)
    }
}
