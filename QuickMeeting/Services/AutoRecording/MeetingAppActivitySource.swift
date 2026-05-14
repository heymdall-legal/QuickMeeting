//
//  MeetingAppActivitySource.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Foundation

protocol MeetingAppActivitySource: Sendable {
    func sample(for app: AutoRecordingApp) -> MeetingAppActivitySample
}
