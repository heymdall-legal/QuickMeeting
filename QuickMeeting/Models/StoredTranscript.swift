//
//  StoredTranscript.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation

struct StoredTranscript: Codable, Equatable, Sendable {
    var speakers: [TranscriptSpeaker]
    var segments: [TranscriptSegment]

    var fullText: String {
        segments
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
