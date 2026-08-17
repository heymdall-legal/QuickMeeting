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

    @discardableResult
    func appendCentroid(
        _ values: [Double],
        to speakerID: String,
        sourceMeetingID: UUID?,
        sourceSpeakerID: String?,
        now: Date
    ) throws -> Bool {
        guard let speaker = try speaker(id: speakerID) else {
            return false
        }
        let isDuplicate = speaker.centroids.contains { existing in
            existing.values == values
                || Self.cosineSimilarity(existing.values, values) >= 0.995
        }
        guard !isDuplicate else {
            return false
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
        return true
    }

    private static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = 0.0
        var lhsNorm = 0.0
        var rhsNorm = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }
        let denominator = sqrt(lhsNorm) * sqrt(rhsNorm)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }
}
