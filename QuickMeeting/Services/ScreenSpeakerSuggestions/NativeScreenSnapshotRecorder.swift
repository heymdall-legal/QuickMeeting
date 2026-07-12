//
//  NativeScreenSnapshotRecorder.swift
//  QuickMeeting
//

import Foundation

#if canImport(ScreenCaptureKit) && canImport(Vision)
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct NativeScreenSnapshotRecorder: ScreenSnapshotRecording {
    let meetingFileStore: MeetingFileStore
    let attendeeNamesProvider: @Sendable (UUID) async -> [String]
    private let analyzer = NativeScreenObservationAnalyzer()

    func capture(
        meetingID: UUID,
        meetingFolderURL: URL,
        startedAt: Date,
        sequenceNumber: Int
    ) async throws -> ScreenObservation? {
        let cgImage = try await captureMainDisplayImage()

        let directory = try await MainActor.run {
            try meetingFileStore.screenObservationsDirectory(forMeetingFolder: meetingFolderURL)
        }
        let imageURL = directory.appendingPathComponent(String(format: "%04d.jpg", sequenceNumber))
        let thumbnailURL = directory.appendingPathComponent(String(format: "%04d-thumb.jpg", sequenceNumber))

        try writeJPEG(cgImage, to: imageURL, maxPixelWidth: 1_600)
        try writeJPEG(cgImage, to: thumbnailURL, maxPixelWidth: 320)

        let textBoxes = await analyzer.textBoxes(in: cgImage)
        let attendeeNames = await attendeeNamesProvider(meetingID)
        let candidateTiles = analyzer.candidateTiles(in: cgImage, textBoxes: textBoxes)
        let activeTile = analyzer.activeTile(
            sourceWindowTitle: nil,
            textBoxes: textBoxes,
            candidateTiles: candidateTiles,
            attendeeNames: attendeeNames
        )

        return ScreenObservation(
            meetingID: meetingID,
            capturedAtOffset: Date().timeIntervalSince(startedAt),
            imageRelativePath: try await MainActor.run {
                try meetingFileStore.relativePath(for: imageURL, inMeetingFolder: meetingFolderURL)
            },
            thumbnailRelativePath: try await MainActor.run {
                try meetingFileStore.relativePath(for: thumbnailURL, inMeetingFolder: meetingFolderURL)
            },
            sourceAppBundleID: nil,
            sourceWindowTitle: nil,
            textBoxes: textBoxes,
            activeTile: activeTile
        )
    }

    private func captureMainDisplayImage() async throws -> CGImage {
        let shareableContent: SCShareableContent = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<SCShareableContent, Error>) in
            SCShareableContent.getExcludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            ) { shareableContent, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let shareableContent else {
                    continuation.resume(throwing: NativeScreenSnapshotRecorderError.noShareableDisplay)
                    return
                }

                continuation.resume(returning: shareableContent)
            }
        }

        guard let display = shareableContent.displays.first else {
            throw NativeScreenSnapshotRecorderError.noShareableDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = max(display.width, 2)
        configuration.height = max(display.height, 2)
        configuration.capturesAudio = false

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image else {
                    continuation.resume(throwing: NativeScreenSnapshotRecorderError.screenshotUnavailable)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    private func writeJPEG(_ image: CGImage, to url: URL, maxPixelWidth: CGFloat) throws {
        let sourceSize = CGSize(width: image.width, height: image.height)
        let targetWidth = min(maxPixelWidth, sourceSize.width)
        let scale = targetWidth / sourceSize.width
        let targetSize = CGSize(width: targetWidth, height: sourceSize.height * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(origin: .zero, size: targetSize))

        guard
            let scaledImage = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return
        }

        CGImageDestinationAddImage(
            destination,
            scaledImage,
            [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary
        )
        CGImageDestinationFinalize(destination)
    }
}

private enum NativeScreenSnapshotRecorderError: Error {
    case noShareableDisplay
    case screenshotUnavailable
}
#endif
