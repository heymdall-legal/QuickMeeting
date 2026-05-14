//
//  MicrophoneActivitySource.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Foundation

protocol MicrophoneActivitySource: Sendable {
    func isMicrophoneActive() -> Bool
}

