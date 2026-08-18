//
//  AutoRecordingSettings.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Foundation

nonisolated enum AutoRecordingApp: String, CaseIterable, Codable, Equatable, Sendable {
    case tolk

    var displayName: String {
        switch self {
        case .tolk:
            "Толк"
        }
    }

    var defaultTarget: AutoRecordingTarget {
        switch self {
        case .tolk:
            .legacyTolk
        }
    }
}

nonisolated struct AutoRecordingTarget: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let appPath: String

    static let legacyTolk = AutoRecordingTarget(
        bundleIdentifier: "kontur.talk",
        displayName: "Толк",
        appPath: ""
    )

    var legacyApp: AutoRecordingApp? {
        switch bundleIdentifier {
        case "kontur.talk":
            return .tolk
        default:
            return nil
        }
    }
}

nonisolated struct AutoRecordingSettings: Equatable, Sendable {
    var isEnabled: Bool
    var selectedApps: [AutoRecordingTarget]
    var startDelay: TimeInterval
    var stopGracePeriod: TimeInterval

    init(
        isEnabled: Bool,
        selectedApps: [AutoRecordingTarget],
        startDelay: TimeInterval,
        stopGracePeriod: TimeInterval
    ) {
        self.isEnabled = isEnabled
        self.selectedApps = selectedApps
        self.startDelay = startDelay
        self.stopGracePeriod = stopGracePeriod
    }

    init(
        isEnabled: Bool,
        selectedApp: AutoRecordingApp,
        startDelay: TimeInterval,
        stopGracePeriod: TimeInterval
    ) {
        self.init(
            isEnabled: isEnabled,
            selectedApps: [selectedApp.defaultTarget],
            startDelay: startDelay,
            stopGracePeriod: stopGracePeriod
        )
    }

    var selectedApp: AutoRecordingApp {
        selectedApps.first?.legacyApp ?? .tolk
    }

    static let `default` = AutoRecordingSettings(
        isEnabled: false,
        selectedApps: [],
        startDelay: 10,
        stopGracePeriod: 60
    )
}
