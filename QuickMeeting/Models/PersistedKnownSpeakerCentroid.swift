//
//  PersistedKnownSpeakerCentroid.swift
//  QuickMeeting
//
//  Created by Codex on 11.06.2026.
//

import Foundation
import SwiftData

@Model
final class PersistedKnownSpeakerCentroid {
    var values: [Double]
    var sourceMeetingID: UUID?
    var sourceSpeakerID: String?
    var createdAt: Date

    init(
        values: [Double],
        sourceMeetingID: UUID?,
        sourceSpeakerID: String?,
        createdAt: Date
    ) {
        self.values = values
        self.sourceMeetingID = sourceMeetingID
        self.sourceSpeakerID = sourceSpeakerID
        self.createdAt = createdAt
    }
}
