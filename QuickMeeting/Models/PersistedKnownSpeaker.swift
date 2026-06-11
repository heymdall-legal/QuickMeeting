//
//  PersistedKnownSpeaker.swift
//  QuickMeeting
//
//  Created by Codex on 11.06.2026.
//

import Foundation
import SwiftData

@Model
final class PersistedKnownSpeaker {
    @Attribute(.unique) var id: String
    var displayName: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var centroids: [PersistedKnownSpeakerCentroid]

    init(
        id: String = UUID().uuidString,
        displayName: String,
        createdAt: Date,
        updatedAt: Date,
        centroids: [PersistedKnownSpeakerCentroid] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.centroids = centroids
    }
}
