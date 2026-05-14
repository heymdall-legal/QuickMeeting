//
//  AutoRecordingSettings.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Foundation

enum AutoRecordingApp: String, CaseIterable, Codable, Equatable, Sendable {
    case tolk

    var displayName: String {
        switch self {
        case .tolk:
            "Толк"
        }
    }
}

struct AutoRecordingSettings: Equatable, Sendable {
    var isEnabled: Bool
    var selectedApp: AutoRecordingApp
    var startDelay: TimeInterval
    var stopGracePeriod: TimeInterval

    static let `default` = AutoRecordingSettings(
        isEnabled: false,
        selectedApp: .tolk,
        startDelay: 10,
        stopGracePeriod: 60
    )
}
