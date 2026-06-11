//
//  KnownSpeakerStore.swift
//  QuickMeeting
//
//  Created by Codex on 11.06.2026.
//

import Foundation
import SwiftData

@MainActor
struct KnownSpeakerStore {
    let modelContext: ModelContext

    func allSpeakers() throws -> [PersistedKnownSpeaker] {
        try modelContext.fetch(FetchDescriptor<PersistedKnownSpeaker>())
    }

    func findSpeaker(exactName displayName: String) throws -> PersistedKnownSpeaker? {
        let normalized = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        guard !normalized.isEmpty else {
            return nil
        }

        return try allSpeakers().first {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == normalized
        }
    }

    @discardableResult
    func findOrCreateSpeaker(named displayName: String, now: Date) throws -> PersistedKnownSpeaker {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = try findSpeaker(exactName: trimmed) {
            return existing
        }

        let speaker = PersistedKnownSpeaker(displayName: trimmed, createdAt: now, updatedAt: now)
        modelContext.insert(speaker)
        try modelContext.save()
        return speaker
    }

    func speaker(id: String) throws -> PersistedKnownSpeaker? {
        let descriptor = FetchDescriptor<PersistedKnownSpeaker>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func appendCentroid(
        _ values: [Double],
        to speakerID: String,
        sourceMeetingID: UUID?,
        sourceSpeakerID: String?,
        now: Date
    ) throws {
        guard let speaker = try speaker(id: speakerID) else {
            return
        }

        speaker.centroids.append(
            PersistedKnownSpeakerCentroid(
                values: values,
                sourceMeetingID: sourceMeetingID,
                sourceSpeakerID: sourceSpeakerID,
                createdAt: now
            )
        )
        speaker.centroids.sort { $0.createdAt < $1.createdAt }
        while speaker.centroids.count > 3 {
            let removed = speaker.centroids.removeFirst()
            modelContext.delete(removed)
        }
        speaker.updatedAt = now
        try modelContext.save()
    }
}
