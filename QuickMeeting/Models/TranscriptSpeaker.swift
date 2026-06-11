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
    var labelSource: TranscriptSpeakerLabelSource
    var matchedKnownSpeakerID: String?
    var centroid: [Double]?

    init(
        id: String,
        displayName: String,
        labelSource: TranscriptSpeakerLabelSource = .generic,
        matchedKnownSpeakerID: String? = nil,
        centroid: [Double]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.labelSource = labelSource
        self.matchedKnownSpeakerID = matchedKnownSpeakerID
        self.centroid = centroid
    }
}
