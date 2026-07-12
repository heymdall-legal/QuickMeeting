//
//  ScreenObservationStore.swift
//  QuickMeeting
//

import Foundation
import SwiftData

@MainActor
struct ScreenObservationStore {
    let modelContext: ModelContext

    func saveObservation(_ observation: ScreenObservation) throws {
        modelContext.insert(PersistedScreenObservation(observation))
        try modelContext.save()
    }

    func observations(for meetingID: UUID) throws -> [ScreenObservation] {
        let descriptor = FetchDescriptor<PersistedScreenObservation>(
            predicate: #Predicate { $0.meetingID == meetingID },
            sortBy: [SortDescriptor(\.capturedAtOffset)]
        )
        return try modelContext.fetch(descriptor).map(\.value)
    }

    func saveSuggestions(_ suggestions: [SpeakerIdentitySuggestion]) throws {
        for suggestion in suggestions {
            modelContext.insert(PersistedSpeakerIdentitySuggestion(suggestion))
        }
        try modelContext.save()
    }

    func suggestions(for meetingID: UUID) throws -> [SpeakerIdentitySuggestion] {
        let descriptor = FetchDescriptor<PersistedSpeakerIdentitySuggestion>(
            predicate: #Predicate { $0.meetingID == meetingID },
            sortBy: [SortDescriptor(\.capturedAtOffset)]
        )
        return try modelContext.fetch(descriptor).map(\.value)
    }

    func pendingSuggestions(for meetingID: UUID) throws -> [SpeakerIdentitySuggestion] {
        try suggestions(for: meetingID).filter { $0.status == .pending }
    }

    func dismissedKeys(for meetingID: UUID) throws -> Set<SpeakerIdentitySuggestionKey> {
        Set(
            try suggestions(for: meetingID)
                .filter { $0.status == .dismissed }
                .map(\.key)
        )
    }

    func replacePendingSuggestions(
        for meetingID: UUID,
        with suggestions: [SpeakerIdentitySuggestion]
    ) throws {
        let pendingStatus = SpeakerIdentitySuggestionStatus.pending.rawValue
        let descriptor = FetchDescriptor<PersistedSpeakerIdentitySuggestion>(
            predicate: #Predicate {
                $0.meetingID == meetingID && $0.statusRawValue == pendingStatus
            }
        )
        for existing in try modelContext.fetch(descriptor) {
            modelContext.delete(existing)
        }
        for suggestion in suggestions {
            modelContext.insert(PersistedSpeakerIdentitySuggestion(suggestion))
        }
        try modelContext.save()
    }

    func updateSuggestionStatus(
        suggestionID: UUID,
        status: SpeakerIdentitySuggestionStatus
    ) throws {
        let descriptor = FetchDescriptor<PersistedSpeakerIdentitySuggestion>(
            predicate: #Predicate { $0.id == suggestionID }
        )
        guard let suggestion = try modelContext.fetch(descriptor).first else {
            return
        }
        suggestion.statusRawValue = status.rawValue
        try modelContext.save()
    }
}
