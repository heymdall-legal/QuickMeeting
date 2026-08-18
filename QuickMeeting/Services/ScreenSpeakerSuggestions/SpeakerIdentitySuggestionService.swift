//
//  SpeakerIdentitySuggestionService.swift
//  QuickMeeting
//

import Foundation

@MainActor
protocol SpeakerSuggestionRecomputing: AnyObject {
    func recomputeSuggestions(for meetingID: UUID) async
    func pendingSuggestions(for meetingID: UUID) -> [SpeakerIdentitySuggestion]
    func acceptSuggestion(id: UUID)
    func dismissSuggestion(id: UUID)
}

struct SpeakerIdentitySuggestionService {
    struct Configuration: Equatable, Sendable {
        var observationWindowRadius: TimeInterval = 1
        var minimumSpeakerDominance = 0.65
        var minimumAttributionMargin = 0.20
        var minimumSupportingObservations = 2
        var minimumSupportingDuration: TimeInterval = 2
        var minimumCandidateShare = 0.65
        var minimumCandidateMargin = 0.20
        var minimumConfidenceScore = 0.60
        var fullDurationSupport: TimeInterval = 6
        var fullObservationSupport = 4
    }

    private struct EvidenceKey: Hashable {
        let speakerID: String
        let attendeeName: String
    }

    private struct AttributedObservation {
        let observation: ScreenObservation
        let overlapDuration: TimeInterval
        let visualConfidence: Double
        let weight: Double
    }

    private struct EvidenceAggregate {
        var observations: [AttributedObservation] = []
        var weight: Double = 0
        var supportingDuration: TimeInterval = 0
        var visualConfidenceTotal: Double = 0

        mutating func append(_ evidence: AttributedObservation) {
            observations.append(evidence)
            weight += evidence.weight
            supportingDuration += evidence.overlapDuration
            visualConfidenceTotal += evidence.visualConfidence
        }

        var averageVisualConfidence: Double {
            guard !observations.isEmpty else { return 0 }
            return visualConfidenceTotal / Double(observations.count)
        }
    }

    private let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func suggestions(
        meetingID: UUID,
        attendeeNames: [String],
        transcript: StoredTranscript?,
        observations: [ScreenObservation],
        dismissed: Set<SpeakerIdentitySuggestionKey>
    ) -> [SpeakerIdentitySuggestion] {
        guard let transcript else {
            return []
        }

        let attendeeLookup = attendeeNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String: String]()) { result, name in
                result[name.localizedLowercase] = result[name.localizedLowercase] ?? name
            }
        guard !attendeeLookup.isEmpty else {
            return []
        }

        let eligibleSpeakerIDs = Set(
            transcript.speakers
                .filter { $0.labelSource == .generic }
                .map(\.id)
        )
        guard !eligibleSpeakerIDs.isEmpty else {
            return []
        }

        var evidenceByCandidate = [EvidenceKey: EvidenceAggregate]()
        for observation in observations.sorted(by: { $0.capturedAtOffset < $1.capturedAtOffset }) {
            guard let activeTile = observation.activeTile,
                  let matchedName = activeTile.matchedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let attendeeName = attendeeLookup[matchedName.localizedLowercase],
                  let attribution = speakerAttribution(
                    at: observation.capturedAtOffset,
                    in: transcript,
                    eligibleSpeakerIDs: eligibleSpeakerIDs
                  )
            else {
                continue
            }

            let visualConfidence = min(max(activeTile.highlightScore, 0), 1)
            let evidence = AttributedObservation(
                observation: observation,
                overlapDuration: attribution.overlapDuration,
                visualConfidence: visualConfidence,
                weight: attribution.overlapDuration * visualConfidence * attribution.dominance
            )
            let key = EvidenceKey(speakerID: attribution.speakerID, attendeeName: attendeeName)
            evidenceByCandidate[key, default: EvidenceAggregate()].append(evidence)
        }

        let aggregatesBySpeaker = Dictionary(grouping: evidenceByCandidate) { entry in
            entry.key.speakerID
        }
        var suggestions = [SpeakerIdentitySuggestion]()

        for (speakerID, entries) in aggregatesBySpeaker {
            let ranked = entries.sorted {
                if $0.value.weight != $1.value.weight {
                    return $0.value.weight > $1.value.weight
                }
                return $0.key.attendeeName < $1.key.attendeeName
            }
            guard let best = ranked.first else { continue }
            let runnerUp = ranked.dropFirst().first
            let totalWeight = ranked.reduce(0) { $0 + $1.value.weight }
            guard totalWeight > 0 else { continue }

            let candidateShare = best.value.weight / totalWeight
            let runnerUpShare = runnerUp.map { $0.value.weight / totalWeight }
            let candidateMargin = runnerUp.map {
                (best.value.weight - $0.value.weight) / max(best.value.weight, 0.000_001)
            } ?? 1
            guard best.value.observations.count >= configuration.minimumSupportingObservations,
                  best.value.supportingDuration >= configuration.minimumSupportingDuration,
                  candidateShare >= configuration.minimumCandidateShare,
                  candidateMargin >= configuration.minimumCandidateMargin
            else {
                continue
            }

            let repeatability = min(
                Double(best.value.observations.count)
                    / Double(max(1, configuration.fullObservationSupport)),
                1
            )
            let durationSupport = min(
                best.value.supportingDuration / max(0.001, configuration.fullDurationSupport),
                1
            )
            let rawConfidence = 0.40 * candidateShare
                + 0.25 * candidateMargin
                + 0.20 * best.value.averageVisualConfidence
                + 0.15 * repeatability
            let confidenceScore = min(
                max(rawConfidence * (0.55 + 0.45 * durationSupport), 0),
                1
            )
            guard confidenceScore >= configuration.minimumConfidenceScore else { continue }

            let suggestionKey = SpeakerIdentitySuggestionKey(
                speakerID: speakerID,
                proposedName: best.key.attendeeName
            )
            guard !dismissed.contains(suggestionKey),
                  let primaryEvidence = best.value.observations.max(by: {
                    $0.weight < $1.weight
                  })?.observation
            else {
                continue
            }

            let evidenceSummary = SpeakerIdentityEvidenceSummary(
                observationIDs: best.value.observations.map(\.observation.id),
                supportingObservationCount: best.value.observations.count,
                supportingDuration: best.value.supportingDuration,
                candidateShare: candidateShare,
                averageVisualConfidence: best.value.averageVisualConfidence,
                runnerUpName: runnerUp?.key.attendeeName,
                runnerUpShare: runnerUpShare
            )
            suggestions.append(SpeakerIdentitySuggestion(
                meetingID: meetingID,
                speakerID: speakerID,
                proposedName: best.key.attendeeName,
                confidence: confidence(for: confidenceScore),
                confidenceScore: confidenceScore,
                evidenceSummary: evidenceSummary,
                reason: "Active speaker evidence",
                evidenceImageRelativePath: primaryEvidence.imageRelativePath,
                evidenceThumbnailRelativePath: primaryEvidence.thumbnailRelativePath,
                observationID: primaryEvidence.id,
                capturedAtOffset: primaryEvidence.capturedAtOffset
            ))
        }

        return suggestions.sorted {
            if $0.capturedAtOffset != $1.capturedAtOffset {
                return $0.capturedAtOffset < $1.capturedAtOffset
            }
            return $0.speakerID < $1.speakerID
        }
    }

    private func speakerAttribution(
        at offset: TimeInterval,
        in transcript: StoredTranscript,
        eligibleSpeakerIDs: Set<String>
    ) -> (speakerID: String, overlapDuration: TimeInterval, dominance: Double)? {
        let windowStart = max(0, offset - configuration.observationWindowRadius)
        let windowEnd = offset + configuration.observationWindowRadius
        var overlapBySpeaker = [String: TimeInterval]()

        for segment in transcript.segments {
            guard let speakerID = segment.speakerID,
                  eligibleSpeakerIDs.contains(speakerID),
                  let rawStart = segment.startTime,
                  let rawEnd = segment.endTime else {
                continue
            }
            let start = min(rawStart, rawEnd)
            let end = max(rawStart, rawEnd)
            let overlap = max(0, min(windowEnd, end) - max(windowStart, start))
            if overlap > 0 {
                overlapBySpeaker[speakerID, default: 0] += overlap
            }
        }

        let ranked = overlapBySpeaker.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }
        guard let best = ranked.first else { return nil }
        let total = ranked.reduce(0) { $0 + $1.value }
        guard total > 0 else { return nil }
        let dominance = best.value / total
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        let margin = (best.value - runnerUp) / max(best.value, 0.000_001)
        guard dominance >= configuration.minimumSpeakerDominance,
              margin >= configuration.minimumAttributionMargin else {
            return nil
        }
        return (best.key, best.value, dominance)
    }

    private func confidence(for score: Double) -> SpeakerIdentitySuggestionConfidence {
        if score >= 0.85 {
            return .high
        }
        if score >= 0.70 {
            return .medium
        }
        return .low
    }
}

@MainActor
final class DefaultSpeakerSuggestionRecomputeService: SpeakerSuggestionRecomputing {
    private let meetingStore: MeetingStore
    private let observationStore: ScreenObservationStore
    private let scorer: SpeakerIdentitySuggestionService

    convenience init(
        meetingStore: MeetingStore,
        observationStore: ScreenObservationStore
    ) {
        self.init(
            meetingStore: meetingStore,
            observationStore: observationStore,
            scorer: SpeakerIdentitySuggestionService()
        )
    }

    init(
        meetingStore: MeetingStore,
        observationStore: ScreenObservationStore,
        scorer: SpeakerIdentitySuggestionService
    ) {
        self.meetingStore = meetingStore
        self.observationStore = observationStore
        self.scorer = scorer
    }

    func recomputeSuggestions(for meetingID: UUID) async {
        do {
            let meeting = try meetingStore.fetchMeeting(id: meetingID)
            let observations = try observationStore.observations(for: meetingID)
            let dismissed = try observationStore.dismissedKeys(for: meetingID)
            let suggestions = scorer.suggestions(
                meetingID: meetingID,
                attendeeNames: meeting.attendeeNames,
                transcript: meeting.storedTranscript,
                observations: observations,
                dismissed: dismissed
            )
            try observationStore.replacePendingSuggestions(for: meetingID, with: suggestions)
        } catch {
            // Speaker suggestions are opportunistic; never block core meeting flows.
        }
    }

    func pendingSuggestions(for meetingID: UUID) -> [SpeakerIdentitySuggestion] {
        (try? observationStore.pendingSuggestions(for: meetingID)) ?? []
    }

    func acceptSuggestion(id: UUID) {
        try? observationStore.updateSuggestionStatus(suggestionID: id, status: .accepted)
    }

    func dismissSuggestion(id: UUID) {
        try? observationStore.updateSuggestionStatus(suggestionID: id, status: .dismissed)
    }
}
