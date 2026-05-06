//
//  TranscriptSpeaker.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation

struct TranscriptSpeaker: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var displayName: String
}
