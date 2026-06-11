//
//  SpeakerRecognitionMapper.swift
//  QuickMeeting
//
//  Created by Codex on 11.06.2026.
//

import Foundation

struct SpeakerRecognitionMapper {
    private let probabilityThreshold = 0.8

    func makeTranscriptSpeakers(
        sidecarSpeakers: [SidecarCompletedSpeaker],
        segments: [SidecarCompletedSegment],
        knownSpeakerNamesByID: [String: String]
    ) -> [TranscriptSpeaker] {
        if !sidecarSpeakers.isEmpty {
            return sidecarSpeakers.enumerated().map { index, speaker in
                guard
                    let matchedID = speaker.matchedID,
                    let probability = speaker.probability,
                    probability > probabilityThreshold,
                    let matchedName = knownSpeakerNamesByID[matchedID]
                else {
                    return TranscriptSpeaker(
                        id: speaker.id,
                        displayName: "Speaker \(index + 1)",
                        labelSource: .generic,
                        matchedKnownSpeakerID: nil,
                        centroid: speaker.centroid
                    )
                }

                return TranscriptSpeaker(
                    id: speaker.id,
                    displayName: matchedName,
                    labelSource: .bankMatched,
                    matchedKnownSpeakerID: matchedID,
                    centroid: speaker.centroid
                )
            }
        }

        let orderedSpeakerIDs = segments.reduce(into: [String]()) { result, segment in
            if !result.contains(segment.speaker) {
                result.append(segment.speaker)
            }
        }

        return orderedSpeakerIDs.enumerated().map { index, speakerID in
            TranscriptSpeaker(id: speakerID, displayName: "Speaker \(index + 1)")
        }
    }
}
