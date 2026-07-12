//
//  KonturTalkScreenAnalyzer.swift
//  QuickMeeting
//

import Foundation

struct KonturTalkScreenAnalyzer: MeetingScreenAnalyzing {
    private let minimumHighlightScore = 0.75

    func matchesContext(sourceWindowTitle: String?, textBoxes: [ScreenTextObservation]) -> Bool {
        if sourceWindowTitle?.localizedCaseInsensitiveContains("kontur") == true {
            return true
        }
        if sourceWindowTitle?.localizedCaseInsensitiveContains("talk") == true {
            return true
        }
        return textBoxes.contains {
            $0.text.localizedCaseInsensitiveContains("kontur")
                || $0.text.localizedCaseInsensitiveContains("talk")
        }
    }

    func activeTile(
        candidates: [CandidateScreenTile],
        textBoxes: [ScreenTextObservation],
        attendeeNames: [String]
    ) -> ScreenTileObservation? {
        guard let candidate = candidates.max(by: { $0.highlightScore < $1.highlightScore }),
              candidate.highlightScore >= minimumHighlightScore else {
            return nil
        }

        let attendeeLookup = attendeeNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let matchedName = textBoxes
            .filter { candidate.boundingBox.contains(centerOf: $0.boundingBox) }
            .compactMap { textBox in
                attendeeLookup.first {
                    textBox.text.localizedCaseInsensitiveContains($0)
                        || $0.localizedCaseInsensitiveContains(textBox.text)
                }
            }
            .first

        guard let matchedName else {
            return nil
        }

        return ScreenTileObservation(
            boundingBox: candidate.boundingBox,
            matchedName: matchedName,
            highlightScore: candidate.highlightScore
        )
    }
}
