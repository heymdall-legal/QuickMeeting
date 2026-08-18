import Foundation
import Testing
@testable import QuickMeeting

#if canImport(CoreGraphics) && canImport(Vision)
import CoreGraphics
#endif

struct KonturTalkScreenAnalyzerTests {
    #if canImport(CoreGraphics) && canImport(Vision)
    @Test
    func imageBorderContrastProducesRelativeHighlightScore() throws {
        let image = try #require(makeHighlightFixture())
        let analyzer = NativeScreenObservationAnalyzer()
        let candidates = analyzer.candidateTiles(in: image, textBoxes: [
            ScreenTextObservation(
                text: "Masha",
                boundingBox: UnitRect(x: 0.1, y: 0.25, width: 0.1, height: 0.04)
            ),
            ScreenTextObservation(
                text: "Ilya",
                boundingBox: UnitRect(x: 0.6, y: 0.25, width: 0.1, height: 0.04)
            ),
        ])

        #expect(candidates.count == 2)
        #expect(candidates[1].highlightScore > candidates[0].highlightScore + 0.08)
        #expect(candidates[1].highlightScore >= 0.55)
    }
    #endif

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
    func equallyHighlightedAttendeesRemainAmbiguous() {
        let analyzer = KonturTalkScreenAnalyzer()
        let activeTile = analyzer.activeTile(
            candidates: [
                CandidateScreenTile(
                    boundingBox: UnitRect(x: 0, y: 0, width: 0.4, height: 0.4),
                    highlightScore: 0.82
                ),
                CandidateScreenTile(
                    boundingBox: UnitRect(x: 0.5, y: 0, width: 0.4, height: 0.4),
                    highlightScore: 0.80
                ),
            ],
            textBoxes: [
                ScreenTextObservation(text: "Masha", boundingBox: UnitRect(x: 0.1, y: 0.1, width: 0.1, height: 0.05)),
                ScreenTextObservation(text: "Ilya", boundingBox: UnitRect(x: 0.6, y: 0.1, width: 0.1, height: 0.05)),
            ],
            attendeeNames: ["Masha", "Ilya"]
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

#if canImport(CoreGraphics) && canImport(Vision)
private func makeHighlightFixture() -> CGImage? {
    let width = 320
    let height = 200
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    context.setFillColor(CGColor(gray: 0.15, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let leftTile = CGRect(x: 13, y: 5, width: 128, height: 64)
    let rightTile = CGRect(x: 173, y: 5, width: 128, height: 64)
    context.setFillColor(CGColor(gray: 0.25, alpha: 1))
    context.fill(leftTile)
    context.fill(rightTile)
    context.setStrokeColor(CGColor(red: 0.1, green: 0.95, blue: 0.35, alpha: 1))
    context.setLineWidth(10)
    context.stroke(rightTile.insetBy(dx: 1, dy: 1))
    return context.makeImage()
}
#endif
