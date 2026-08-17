import Foundation

nonisolated enum TranscriptEventSource: String, Codable, Sendable {
    case online
}

nonisolated struct OnlineDraftEvent: Codable, Equatable, Identifiable, Sendable {
    var utteranceID: UUID
    var revision: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var onlineSpeakerClusterID: String?
    var isFinalWithinDraft: Bool
    var source: TranscriptEventSource

    var id: UUID { utteranceID }
}

nonisolated struct OnlineDraftTranscript: Codable, Equatable, Sendable {
    private(set) var events: [OnlineDraftEvent]

    init(events: [OnlineDraftEvent] = []) {
        self.events = []
        for event in events {
            upsert(event)
        }
    }

    mutating func upsert(_ event: OnlineDraftEvent) {
        guard event.source == .online else { return }
        if let index = events.firstIndex(where: { $0.utteranceID == event.utteranceID }) {
            guard event.revision > events[index].revision else { return }
            events[index] = event
        } else {
            events.append(event)
        }
        events.sort {
            if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
            return $0.utteranceID.uuidString < $1.utteranceID.uuidString
        }
    }

    var storedTranscript: StoredTranscript {
        let clusterIDs = events.compactMap(\.onlineSpeakerClusterID).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        let speakers = clusterIDs.enumerated().map { index, clusterID in
            TranscriptSpeaker(
                id: clusterID,
                displayName: "Speaker \(index + 1)",
                labelSource: .generic
            )
        }
        let segments = events.compactMap { event -> TranscriptSegment? in
            let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(
                id: event.utteranceID,
                text: text,
                startTime: event.startTime,
                endTime: event.endTime,
                speakerID: event.onlineSpeakerClusterID
            )
        }
        return StoredTranscript(speakers: speakers, segments: segments)
    }
}

nonisolated enum TranscriptLifecycleState: String, Codable, Sendable {
    case recording
    case draftAvailable
    case finalizing
    case finalAvailable
    case finalFailed
}

nonisolated enum VisibleTranscriptVersion: String, Codable, Sendable {
    case draft
    case final
}

/// Versioned JSON envelope stored in the existing metadata Data column. This
/// adds draft/final versioning without changing the SwiftData schema. Legacy
/// rows containing a bare TranscriptionPipelineMetadata are upgraded lazily.
nonisolated struct TranscriptArtifactEnvelope: Codable, Equatable, Sendable {
    var formatVersion: Int = 1
    var lifecycleState: TranscriptLifecycleState
    var visibleVersion: VisibleTranscriptVersion
    var onlineDraft: OnlineDraftTranscript?
    var onlineTelemetry: OnlineDraftTelemetry?
    var finalMetadata: TranscriptionPipelineMetadata?

    init(
        lifecycleState: TranscriptLifecycleState,
        visibleVersion: VisibleTranscriptVersion,
        onlineDraft: OnlineDraftTranscript? = nil,
        onlineTelemetry: OnlineDraftTelemetry? = nil,
        finalMetadata: TranscriptionPipelineMetadata? = nil
    ) {
        self.lifecycleState = lifecycleState
        self.visibleVersion = visibleVersion
        self.onlineDraft = onlineDraft
        self.onlineTelemetry = onlineTelemetry
        self.finalMetadata = finalMetadata
    }
}
