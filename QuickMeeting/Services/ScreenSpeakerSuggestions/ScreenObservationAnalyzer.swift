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

#if canImport(Vision)
import CoreGraphics
import Vision

nonisolated struct NativeScreenObservationAnalyzer {
    private let konturAnalyzer = KonturTalkScreenAnalyzer()

    nonisolated func textBoxes(in image: CGImage) async -> [ScreenTextObservation] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let boxes = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { observation -> ScreenTextObservation? in
                        guard let text = observation.topCandidates(1).first?.string else {
                            return nil
                        }

                        return ScreenTextObservation(
                            text: text,
                            boundingBox: UnitRect(
                                x: observation.boundingBox.minX,
                                y: observation.boundingBox.minY,
                                width: observation.boundingBox.width,
                                height: observation.boundingBox.height
                            )
                        )
                    }
                continuation.resume(returning: boxes)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    nonisolated func candidateTiles(in image: CGImage, textBoxes: [ScreenTextObservation]) -> [CandidateScreenTile] {
        textBoxes.map { textBox in
            let tileWidth = min(0.42, max(0.22, textBox.boundingBox.width * 4))
            let tileHeight = min(0.36, max(0.18, textBox.boundingBox.height * 8))
            let tileX = max(0, min(1 - tileWidth, textBox.boundingBox.x - tileWidth * 0.15))
            let tileY = max(0, min(1 - tileHeight, textBox.boundingBox.y - tileHeight * 0.7))

            return CandidateScreenTile(
                boundingBox: UnitRect(x: tileX, y: tileY, width: tileWidth, height: tileHeight),
                highlightScore: highlightScore(around: textBox.boundingBox, in: image)
            )
        }
    }

    nonisolated func activeTile(
        sourceWindowTitle: String?,
        textBoxes: [ScreenTextObservation],
        candidateTiles: [CandidateScreenTile],
        attendeeNames: [String]
    ) -> ScreenTileObservation? {
        if konturAnalyzer.matchesContext(sourceWindowTitle: sourceWindowTitle, textBoxes: textBoxes) {
            return konturAnalyzer.activeTile(
                candidates: candidateTiles,
                textBoxes: textBoxes,
                attendeeNames: attendeeNames
            )
        }

        return KonturTalkScreenAnalyzer().activeTile(
            candidates: candidateTiles,
            textBoxes: textBoxes,
            attendeeNames: attendeeNames
        )
    }

    private nonisolated func highlightScore(around textBox: UnitRect, in image: CGImage) -> Double {
        guard image.width > 0, image.height > 0, textBox.width > 0, textBox.height > 0 else {
            return 0
        }

        return 0.8
    }
}
#endif
