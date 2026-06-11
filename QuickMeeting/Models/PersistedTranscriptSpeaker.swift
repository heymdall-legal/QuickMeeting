//
//  PersistedTranscriptSpeaker.swift
//  QuickMeeting
//
//  Created by Codex on 07.05.2026.
//

import Foundation
import SwiftData

@Model
final class PersistedTranscriptSpeaker {
    var id: String
    var displayName: String
    var labelSourceRawValue: String?
    var matchedKnownSpeakerID: String?
    var centroid: [Double]?

    init(
        id: String,
        displayName: String,
        labelSourceRawValue: String?,
        matchedKnownSpeakerID: String? = nil,
        centroid: [Double]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.labelSourceRawValue = labelSourceRawValue
        self.matchedKnownSpeakerID = matchedKnownSpeakerID
        self.centroid = centroid
    }

    convenience init(
        id: String,
        displayName: String,
        labelSource: TranscriptSpeakerLabelSource = .generic,
        matchedKnownSpeakerID: String? = nil,
        centroid: [Double]? = nil
    ) {
        self.init(
            id: id,
            displayName: displayName,
            labelSourceRawValue: labelSource.rawValue,
            matchedKnownSpeakerID: matchedKnownSpeakerID,
            centroid: centroid
        )
    }

    convenience init(_ speaker: TranscriptSpeaker) {
        self.init(
            id: speaker.id,
            displayName: speaker.displayName,
            labelSource: speaker.labelSource,
            matchedKnownSpeakerID: speaker.matchedKnownSpeakerID,
            centroid: speaker.centroid
        )
    }

    var value: TranscriptSpeaker {
        TranscriptSpeaker(
            id: id,
            displayName: displayName,
            labelSource: TranscriptSpeakerLabelSource(rawValue: labelSourceRawValue ?? "") ?? .generic,
            matchedKnownSpeakerID: matchedKnownSpeakerID,
            centroid: centroid
        )
    }
}
