//
//  RecordingState.swift
//  QuickMeeting
//
//  Created by Codex on 04.05.2026.
//

import Foundation

enum RecordingState: Equatable {
    case idle
    case starting
    case recording(meetingID: UUID)
    case stopping(meetingID: UUID)
    case failed(message: String)
}
