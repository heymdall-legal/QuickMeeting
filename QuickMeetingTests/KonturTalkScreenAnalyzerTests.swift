import Foundation
import Testing
@testable import QuickMeeting

struct KonturTalkScreenAnalyzerTests {
    @Test
    func detectsKonturTalkFromWindowTitle() {
        let analyzer = KonturTalkScreenAnalyzer()

        #expect(analyzer.matchesContext(sourceWindowTitle: "Kontur Talk - Safari", textBoxes: []))
        #expect(!analyzer.matchesContext(sourceWindowTitle: "Weekly Sync - Safari", textBoxes: []))
    }

    @Test
    func highlightedTileWithAttendeeTextProducesActiveTile() {
        let analyzer = KonturTalkScreenAnalyzer()
        let tiles = [
            CandidateScreenTile(
                boundingBox: UnitRect(x: 0, y: 0, width: 0.4, height: 0.4),
                highlightScore: 0.2
            ),
            CandidateScreenTile(
                boundingBox: UnitRect(x: 0.5, y: 0, width: 0.4, height: 0.4),
                highlightScore: 0.94
            ),
        ]
        let textBoxes = [
            ScreenTextObservation(
                text: "Masha",
                boundingBox: UnitRect(x: 0.58, y: 0.3, width: 0.12, height: 0.04)
            )
        ]

        let activeTile = analyzer.activeTile(
            candidates: tiles,
            textBoxes: textBoxes,
            attendeeNames: ["Masha", "Ilya"]
        )

        #expect(activeTile?.matchedName == "Masha")
        #expect(activeTile?.highlightScore == 0.94)
    }

    @Test
    func weakHighlightDoesNotProduceActiveTile() {
        let analyzer = KonturTalkScreenAnalyzer()
        let activeTile = analyzer.activeTile(
            candidates: [
                CandidateScreenTile(
                    boundingBox: UnitRect(x: 0, y: 0, width: 0.4, height: 0.4),
                    highlightScore: 0.4
                )
            ],
            textBoxes: [
                ScreenTextObservation(text: "Masha", boundingBox: UnitRect(x: 0.1, y: 0.1, width: 0.1, height: 0.05))
            ],
            attendeeNames: ["Masha"]
        )

        #expect(activeTile == nil)
    }

    @Test
    func attendeeTextOutsideHighlightedTileDoesNotProduceActiveTile() {
        let analyzer = KonturTalkScreenAnalyzer()
        let activeTile = analyzer.activeTile(
            candidates: [
                CandidateScreenTile(
                    boundingBox: UnitRect(x: 0, y: 0, width: 0.4, height: 0.4),
                    highlightScore: 0.94
                )
            ],
            textBoxes: [
                ScreenTextObservation(
                    text: "Masha",
                    boundingBox: UnitRect(x: 0.7, y: 0.7, width: 0.1, height: 0.05)
                )
            ],
            attendeeNames: ["Masha"]
        )

        #expect(activeTile == nil)
    }
}
