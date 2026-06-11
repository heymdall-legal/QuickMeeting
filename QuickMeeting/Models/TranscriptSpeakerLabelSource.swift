//
//  TranscriptSpeakerLabelSource.swift
//  QuickMeeting
//
//  Created by Codex on 11.06.2026.
//

import Foundation

enum TranscriptSpeakerLabelSource: String, Codable, Equatable, Sendable {
    case generic
    case userAssigned
    case bankMatched
}
