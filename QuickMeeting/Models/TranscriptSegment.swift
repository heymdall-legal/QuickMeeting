//
//  TranscriptSegment.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Foundation

struct TranscriptSegment: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let speakerID: String?

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        speakerID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speakerID = speakerID
    }
}
