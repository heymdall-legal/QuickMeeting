//
//  NativeMeetingAppActivitySource.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import AppKit
import Foundation

struct NativeMeetingAppActivitySource: MeetingAppActivitySource {
    private let workspace: NSWorkspace
    private let runningApplications: () -> [NSRunningApplication]

    init(
        workspace: NSWorkspace = .shared,
        runningApplications: @escaping () -> [NSRunningApplication] = {
            NSWorkspace.shared.runningApplications
        }
    ) {
        self.workspace = workspace
        self.runningApplications = runningApplications
    }

    func sample(for app: AutoRecordingApp) -> MeetingAppActivitySample {
        let bundleIdentifier = bundleIdentifier(for: app)
        let runningApps = runningApplications().filter { $0.bundleIdentifier == bundleIdentifier }
        let isFrontmost = workspace.frontmostApplication?.bundleIdentifier == bundleIdentifier

        return MeetingAppActivitySample(
            bundleIdentifier: bundleIdentifier,
            isRunning: !runningApps.isEmpty,
            isFrontmost: isFrontmost,
            hadRecentFocus: isFrontmost,
            hasVisibleWindow: !runningApps.isEmpty,
            isUsingMedia: false
        )
    }

    private func bundleIdentifier(for app: AutoRecordingApp) -> String {
        switch app {
        case .tolk:
            return "ru.tolk.desktop"
        }
    }
}
