//
//  KonturTalkScreenAnalyzer.swift
//  QuickMeeting
//

import Foundation

struct KonturTalkScreenAnalyzer: MeetingScreenAnalyzing {
    private let minimumHighlightScore = 0.55
    private let minimumLeadOverRunnerUp = 0.08

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
        let attendeeLookup = attendeeNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let eligible = candidates.compactMap { candidate -> (CandidateScreenTile, String)? in
            let matchedName = textBoxes
                .filter { candidate.boundingBox.contains(centerOf: $0.boundingBox) }
                .compactMap { textBox in
                    attendeeLookup.first {
                        textBox.text.localizedCaseInsensitiveContains($0)
                            || $0.localizedCaseInsensitiveContains(textBox.text)
                    }
                }
                .first
            return matchedName.map { (candidate, $0) }
        }.sorted {
            if $0.0.highlightScore != $1.0.highlightScore {
                return $0.0.highlightScore > $1.0.highlightScore
            }
            return $0.1 < $1.1
        }

        guard let (candidate, matchedName) = eligible.first,
              candidate.highlightScore >= minimumHighlightScore else {
            return nil
        }
        if let runnerUp = eligible.dropFirst().first,
           candidate.highlightScore - runnerUp.0.highlightScore < minimumLeadOverRunnerUp {
            return nil
        }

        return ScreenTileObservation(
            boundingBox: candidate.boundingBox,
            matchedName: matchedName,
            highlightScore: candidate.highlightScore
        )
    }
}
