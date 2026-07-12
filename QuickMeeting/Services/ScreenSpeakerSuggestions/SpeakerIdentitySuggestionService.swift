//
//  SpeakerIdentitySuggestionService.swift
//  QuickMeeting
//

import Foundation

struct SpeakerIdentitySuggestionService {
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

        var suggestionsBySpeaker = [String: SpeakerIdentitySuggestion]()

        for observation in observations.sorted(by: { $0.capturedAtOffset < $1.capturedAtOffset }) {
            guard let activeTile = observation.activeTile,
                  let matchedName = activeTile.matchedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let attendeeName = attendeeLookup[matchedName.localizedLowercase],
                  let speakerID = speakerIDSpeaking(at: observation.capturedAtOffset, in: transcript)
            else {
                continue
            }

            let key = SpeakerIdentitySuggestionKey(speakerID: speakerID, proposedName: attendeeName)
            guard !dismissed.contains(key), suggestionsBySpeaker[speakerID] == nil else {
                continue
            }

            suggestionsBySpeaker[speakerID] = SpeakerIdentitySuggestion(
                meetingID: meetingID,
                speakerID: speakerID,
                proposedName: attendeeName,
                confidence: confidence(for: activeTile),
                reason: "Seen in active tile",
                evidenceImageRelativePath: observation.imageRelativePath,
                evidenceThumbnailRelativePath: observation.thumbnailRelativePath,
                observationID: observation.id,
                capturedAtOffset: observation.capturedAtOffset
            )
        }

        return suggestionsBySpeaker.values.sorted {
            if $0.capturedAtOffset != $1.capturedAtOffset {
                return $0.capturedAtOffset < $1.capturedAtOffset
            }
            return $0.speakerID < $1.speakerID
        }
    }

    private func speakerIDSpeaking(at offset: TimeInterval, in transcript: StoredTranscript) -> String? {
        transcript.segments.first { segment in
            guard let start = segment.startTime, let end = segment.endTime else {
                return false
            }
            return offset >= start && offset <= end
        }?.speakerID
    }

    private func confidence(for activeTile: ScreenTileObservation) -> SpeakerIdentitySuggestionConfidence {
        if activeTile.highlightScore >= 0.85 {
            return .high
        }
        if activeTile.highlightScore >= 0.65 {
            return .medium
        }
        return .low
    }
}
