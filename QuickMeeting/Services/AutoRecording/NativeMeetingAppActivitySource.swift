//
//  NativeMeetingAppActivitySource.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import AppKit
import Foundation

final class NativeMeetingAppActivitySource: MeetingAppActivitySource, @unchecked Sendable {
    private let runningBundleIdentifiers: () -> Set<String>
    private let frontmostBundleIdentifier: () -> String?
    private let visibleWindowBundleIdentifiers: () -> Set<String>
    private let microphoneActivitySource: any MicrophoneActivitySource
    private let now: () -> Date
    private let recentFocusWindow: TimeInterval
    private var lastFocusedAtByBundleIdentifier: [String: Date] = [:]

    init(
        runningBundleIdentifiers: @escaping () -> Set<String> = {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        },
        frontmostBundleIdentifier: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        visibleWindowBundleIdentifiers: @escaping () -> Set<String> = defaultVisibleWindowBundleIdentifiers,
        microphoneActivitySource: any MicrophoneActivitySource = NativeMicrophoneActivitySource(),
        now: @escaping () -> Date = Date.init,
        recentFocusWindow: TimeInterval = 30
    ) {
        self.runningBundleIdentifiers = runningBundleIdentifiers
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.visibleWindowBundleIdentifiers = visibleWindowBundleIdentifiers
        self.microphoneActivitySource = microphoneActivitySource
        self.now = now
        self.recentFocusWindow = recentFocusWindow
    }

    func sample(for app: AutoRecordingApp) -> MeetingAppActivitySample {
        let bundleIdentifier = bundleIdentifier(for: app)
        if let frontmostBundleIdentifier = frontmostBundleIdentifier() {
            lastFocusedAtByBundleIdentifier[frontmostBundleIdentifier] = now()
        }

        let isFrontmost = frontmostBundleIdentifier() == bundleIdentifier
        let hadRecentFocus = lastFocusedAtByBundleIdentifier[bundleIdentifier].map {
            now().timeIntervalSince($0) <= recentFocusWindow
        } ?? false

        return MeetingAppActivitySample(
            bundleIdentifier: bundleIdentifier,
            isRunning: runningBundleIdentifiers().contains(bundleIdentifier),
            isFrontmost: isFrontmost,
            hadRecentFocus: hadRecentFocus,
            hasVisibleWindow: visibleWindowBundleIdentifiers().contains(bundleIdentifier),
            isMicrophoneActive: microphoneActivitySource.isMicrophoneActive()
        )
    }

    private func bundleIdentifier(for app: AutoRecordingApp) -> String {
        switch app {
        case .tolk:
            return "kontur.talk"
        }
    }

}

private func defaultVisibleWindowBundleIdentifiers() -> Set<String> {
    guard let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[CFString: Any]] else {
        return []
    }

    return Set(windowList.compactMap { window in
        guard let layer = window[kCGWindowLayer] as? Int,
              layer == 0,
              let alpha = window[kCGWindowAlpha] as? Double,
              alpha > 0,
              let ownerPID = window[kCGWindowOwnerPID] as? pid_t else {
            return nil
        }

        return NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
    })
}
