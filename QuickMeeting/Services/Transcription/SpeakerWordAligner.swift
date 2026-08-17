import Foundation

nonisolated struct SpeakerInterval: Equatable, Sendable {
    var speakerID: String
    var startTime: TimeInterval
    var endTime: TimeInterval
}

nonisolated enum SpeakerWordAligner {
    static let defaultGapTolerance: TimeInterval = 0.2
    private static let comparisonEpsilon: TimeInterval = 0.001

    static func speakerID(
        for word: TimedWord,
        intervals: [SpeakerInterval],
        gapTolerance: TimeInterval = defaultGapTolerance
    ) -> String? {
        let wordStart = min(word.startTime, word.endTime)
        let wordEnd = max(word.startTime, word.endTime)
        let midpoint = (wordStart + wordEnd) / 2

        struct Score {
            var overlap: TimeInterval = 0
            var containsMidpoint = false
            var nearestGap = TimeInterval.greatestFiniteMagnitude
        }

        var scores: [String: Score] = [:]
        for interval in intervals where interval.endTime >= interval.startTime {
            let overlap = max(
                0,
                min(wordEnd, interval.endTime) - max(wordStart, interval.startTime)
            )
            let gap: TimeInterval
            if overlap > 0 {
                gap = 0
            } else if wordEnd < interval.startTime {
                gap = interval.startTime - wordEnd
            } else if interval.endTime < wordStart {
                gap = wordStart - interval.endTime
            } else {
                gap = 0
            }

            var score = scores[interval.speakerID] ?? Score()
            score.overlap += overlap
            score.containsMidpoint = score.containsMidpoint
                || (interval.startTime <= midpoint && midpoint < interval.endTime)
            score.nearestGap = min(score.nearestGap, gap)
            scores[interval.speakerID] = score
        }

        let overlapping = scores.filter { $0.value.overlap > comparisonEpsilon }
        if !overlapping.isEmpty {
            let maximum = overlapping.values.map(\.overlap).max() ?? 0
            let tied = overlapping.filter {
                abs($0.value.overlap - maximum) <= comparisonEpsilon
            }
            if tied.count == 1 { return tied.first?.key }

            // Midpoint is only a tie-breaker. If overlapping speakers both own
            // it, attribution remains explicitly unknown.
            let midpointOwners = tied.filter(\.value.containsMidpoint)
            return midpointOwners.count == 1 ? midpointOwners.first?.key : nil
        }

        let nearby = scores.filter { $0.value.nearestGap <= max(0, gapTolerance) }
        guard !nearby.isEmpty else { return nil }
        let minimumGap = nearby.values.map(\.nearestGap).min() ?? .greatestFiniteMagnitude
        let closest = nearby.filter {
            abs($0.value.nearestGap - minimumGap) <= comparisonEpsilon
        }
        return closest.count == 1 ? closest.first?.key : nil
    }
}
