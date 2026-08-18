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
        let sampler = ImageColorSampler(image: image)
        return textBoxes.map { textBox in
            let tileWidth = min(0.42, max(0.22, textBox.boundingBox.width * 4))
            let tileHeight = min(0.36, max(0.18, textBox.boundingBox.height * 8))
            let tileX = max(0, min(1 - tileWidth, textBox.boundingBox.x - tileWidth * 0.15))
            let tileY = max(0, min(1 - tileHeight, textBox.boundingBox.y - tileHeight * 0.7))
            let tile = UnitRect(x: tileX, y: tileY, width: tileWidth, height: tileHeight)

            return CandidateScreenTile(
                boundingBox: tile,
                highlightScore: sampler?.highlightScore(around: tile) ?? 0
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

    private nonisolated struct ImageColorSampler {
        private let pixels: [UInt8]
        private let width: Int
        private let height: Int
        private let bytesPerRow: Int

        init?(image: CGImage) {
            let width = min(max(image.width, 2), 320)
            let height = min(max(image.height, 2), 200)
            let bytesPerRow = width * 4
            var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
            let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                ) else {
                    return false
                }
                context.interpolationQuality = .low
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard didDraw else { return nil }
            self.pixels = pixels
            self.width = width
            self.height = height
            self.bytesPerRow = bytesPerRow
        }

        func highlightScore(around rect: UnitRect) -> Double {
            let minX = max(0, min(width - 1, Int(rect.x * Double(width))))
            let maxX = max(minX + 1, min(width, Int((rect.x + rect.width) * Double(width))))
            // Vision uses a bottom-left origin while the rendered pixel buffer is top-left.
            let minY = max(
                0,
                min(height - 1, Int((1 - rect.y - rect.height) * Double(height)))
            )
            let maxY = max(
                minY + 1,
                min(height, Int((1 - rect.y) * Double(height)))
            )
            let rectWidth = maxX - minX
            let rectHeight = maxY - minY
            guard rectWidth >= 4, rectHeight >= 4 else { return 0 }

            let borderBand = max(1, min(rectWidth, rectHeight) / 14)
            let innerInset = max(borderBand + 1, min(rectWidth, rectHeight) / 5)
            var borderLuminance = 0.0
            var borderColorfulness = 0.0
            var borderCount = 0
            var innerLuminance = 0.0
            var innerColorfulness = 0.0
            var innerCount = 0

            for y in stride(from: minY, to: maxY, by: 2) {
                for x in stride(from: minX, to: maxX, by: 2) {
                    let localX = x - minX
                    let localY = y - minY
                    let isBorder = localX < borderBand
                        || localY < borderBand
                        || localX >= rectWidth - borderBand
                        || localY >= rectHeight - borderBand
                    let isInner = localX >= innerInset
                        && localY >= innerInset
                        && localX < rectWidth - innerInset
                        && localY < rectHeight - innerInset
                    guard isBorder || isInner else { continue }

                    let offset = y * bytesPerRow + x * 4
                    let red = Double(pixels[offset]) / 255
                    let green = Double(pixels[offset + 1]) / 255
                    let blue = Double(pixels[offset + 2]) / 255
                    let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                    let colorfulness = max(red, green, blue) - min(red, green, blue)

                    if isBorder {
                        borderLuminance += luminance
                        borderColorfulness += colorfulness
                        borderCount += 1
                    } else if isInner {
                        innerLuminance += luminance
                        innerColorfulness += colorfulness
                        innerCount += 1
                    }
                }
            }

            guard borderCount > 0, innerCount > 0 else { return 0 }
            let borderLum = borderLuminance / Double(borderCount)
            let innerLum = innerLuminance / Double(innerCount)
            let borderChroma = borderColorfulness / Double(borderCount)
            let innerChroma = innerColorfulness / Double(innerCount)
            let chromaLift = max(0, borderChroma - innerChroma)
            let luminanceContrast = abs(borderLum - innerLum)
            return min(max(
                0.25 + 0.50 * chromaLift + 0.90 * luminanceContrast + 0.25 * borderChroma,
                0
            ), 1)
        }
    }
}
#endif
