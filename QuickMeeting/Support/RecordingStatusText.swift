//
//  RecordingStatusText.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation

func recordingStatusText(for recordingState: RecordingState) -> String {
    switch recordingState {
    case .idle:
        return "Ready"
    case .starting:
        return "Starting recording..."
    case .recording:
        return "Recording in progress"
    case .stopping:
        return "Stopping recording..."
    case .failed(let message):
        return message
    }
}
