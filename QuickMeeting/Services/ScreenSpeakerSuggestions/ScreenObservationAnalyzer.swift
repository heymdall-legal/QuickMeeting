//
//  ScreenObservationAnalyzer.swift
//  QuickMeeting
//

import Foundation

nonisolated struct CandidateScreenTile: Equatable, Sendable {
    let boundingBox: UnitRect
    let highlightScore: Double
}

nonisolated protocol MeetingScreenAnalyzing: Sendable {
    func activeTile(
        candidates: [CandidateScreenTile],
        textBoxes: [ScreenTextObservation],
        attendeeNames: [String]
    ) -> ScreenTileObservation?
}
