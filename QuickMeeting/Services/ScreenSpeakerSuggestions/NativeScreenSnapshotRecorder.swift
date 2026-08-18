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

actor NativeScreenSnapshotRecorder: ScreenSnapshotRecording {
    private struct CapturedSurface {
        let image: CGImage
        let sourceAppBundleID: String?
        let sourceWindowTitle: String?
    }

    private struct SavedEvidenceImage {
        let meetingID: UUID
        let speakerName: String
        let capturedAtOffset: TimeInterval
        let imageRelativePath: String
        let thumbnailRelativePath: String
    }

    let meetingFileStore: MeetingFileStore
    let attendeeNamesProvider: @Sendable (UUID) async -> [String]
    private let analyzer = NativeScreenObservationAnalyzer()
    private var lastSavedEvidenceImage: SavedEvidenceImage?
    private let imageRefreshInterval: TimeInterval = 10

    init(
        meetingFileStore: MeetingFileStore,
        attendeeNamesProvider: @escaping @Sendable (UUID) async -> [String]
    ) {
        self.meetingFileStore = meetingFileStore
        self.attendeeNamesProvider = attendeeNamesProvider
    }

    func capture(
        meetingID: UUID,
        meetingFolderURL: URL,
        startedAt: Date,
        sequenceNumber: Int
    ) async throws -> ScreenObservation? {
        let capturedSurface = try await captureMeetingSurfaceImage()
        let cgImage = capturedSurface.image
        let capturedAtOffset = max(0, Date().timeIntervalSince(startedAt))
        let textBoxes = await analyzer.textBoxes(in: cgImage)
        let attendeeNames = await attendeeNamesProvider(meetingID)
        let candidateTiles = analyzer.candidateTiles(in: cgImage, textBoxes: textBoxes)
        guard let activeTile = analyzer.activeTile(
            sourceWindowTitle: capturedSurface.sourceWindowTitle,
            textBoxes: textBoxes,
            candidateTiles: candidateTiles,
            attendeeNames: attendeeNames
        ), let matchedName = activeTile.matchedName else {
            return nil
        }

        let evidencePaths = try await evidenceImagePaths(
            image: cgImage,
            activeTile: activeTile,
            matchedName: matchedName,
            meetingID: meetingID,
            meetingFolderURL: meetingFolderURL,
            sequenceNumber: sequenceNumber,
            capturedAtOffset: capturedAtOffset
        )

        return ScreenObservation(
            meetingID: meetingID,
            capturedAtOffset: capturedAtOffset,
            imageRelativePath: evidencePaths.image,
            thumbnailRelativePath: evidencePaths.thumbnail,
            sourceAppBundleID: capturedSurface.sourceAppBundleID,
            sourceWindowTitle: capturedSurface.sourceWindowTitle,
            textBoxes: textBoxes,
            activeTile: activeTile
        )
    }

    private func evidenceImagePaths(
        image: CGImage,
        activeTile: ScreenTileObservation,
        matchedName: String,
        meetingID: UUID,
        meetingFolderURL: URL,
        sequenceNumber: Int,
        capturedAtOffset: TimeInterval
    ) async throws -> (image: String, thumbnail: String) {
        if let lastSavedEvidenceImage,
           lastSavedEvidenceImage.meetingID == meetingID,
           lastSavedEvidenceImage.speakerName.localizedCaseInsensitiveCompare(matchedName) == .orderedSame,
           capturedAtOffset - lastSavedEvidenceImage.capturedAtOffset < imageRefreshInterval {
            return (
                lastSavedEvidenceImage.imageRelativePath,
                lastSavedEvidenceImage.thumbnailRelativePath
            )
        }

        let directory = try await MainActor.run {
            try meetingFileStore.screenObservationsDirectory(forMeetingFolder: meetingFolderURL)
        }
        let imageURL = directory.appendingPathComponent(String(format: "%04d.jpg", sequenceNumber))
        let thumbnailURL = directory.appendingPathComponent(String(format: "%04d-thumb.jpg", sequenceNumber))
        let evidenceImage = croppedEvidenceImage(from: image, tile: activeTile.boundingBox) ?? image

        try writeJPEG(evidenceImage, to: imageURL, maxPixelWidth: 1_000)
        try writeJPEG(evidenceImage, to: thumbnailURL, maxPixelWidth: 320)

        let relativePaths = try await MainActor.run {
            (
                try meetingFileStore.relativePath(for: imageURL, inMeetingFolder: meetingFolderURL),
                try meetingFileStore.relativePath(for: thumbnailURL, inMeetingFolder: meetingFolderURL)
            )
        }
        lastSavedEvidenceImage = SavedEvidenceImage(
            meetingID: meetingID,
            speakerName: matchedName,
            capturedAtOffset: capturedAtOffset,
            imageRelativePath: relativePaths.0,
            thumbnailRelativePath: relativePaths.1
        )
        return (relativePaths.0, relativePaths.1)
    }

    private func croppedEvidenceImage(from image: CGImage, tile: UnitRect) -> CGImage? {
        let padding = 0.025
        let x = max(0, tile.x - padding)
        let y = max(0, tile.y - padding)
        let width = min(1 - x, tile.width + padding * 2)
        let height = min(1 - y, tile.height + padding * 2)
        guard width > 0, height > 0 else { return nil }

        // Vision rectangles use a bottom-left origin; CGImage cropping uses top-left.
        let pixelRect = CGRect(
            x: x * Double(image.width),
            y: (1 - y - height) * Double(image.height),
            width: width * Double(image.width),
            height: height * Double(image.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !pixelRect.isNull, pixelRect.width > 1, pixelRect.height > 1 else { return nil }
        return image.cropping(to: pixelRect)
    }

    private func captureMeetingSurfaceImage() async throws -> CapturedSurface {
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

        if let meetingWindow = preferredMeetingWindow(in: shareableContent.windows) {
            let filter = SCContentFilter(desktopIndependentWindow: meetingWindow)
            let image = try await captureImage(
                filter: filter,
                width: max(Int(meetingWindow.frame.width), 2),
                height: max(Int(meetingWindow.frame.height), 2)
            )
            return CapturedSurface(
                image: image,
                sourceAppBundleID: meetingWindow.owningApplication?.bundleIdentifier,
                sourceWindowTitle: meetingWindow.title
            )
        }

        guard let display = shareableContent.displays.first else {
            throw NativeScreenSnapshotRecorderError.noShareableDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return CapturedSurface(
            image: try await captureImage(
                filter: filter,
                width: max(display.width, 2),
                height: max(display.height, 2)
            ),
            sourceAppBundleID: nil,
            sourceWindowTitle: nil
        )
    }

    private func preferredMeetingWindow(in windows: [SCWindow]) -> SCWindow? {
        windows
            .filter { window in
                window.isOnScreen
                    && window.frame.width >= 480
                    && window.frame.height >= 320
            }
            .compactMap { window -> (window: SCWindow, score: Int, area: CGFloat)? in
                let title = window.title?.localizedLowercase ?? ""
                let appName = window.owningApplication?.applicationName.localizedLowercase ?? ""
                let combined = "\(title) \(appName)"
                let score: Int
                if combined.contains("контур") || combined.contains("kontur") {
                    score = 3
                } else if combined.contains("толк") || combined.contains("talk") {
                    score = 2
                } else {
                    return nil
                }
                return (window, score, window.frame.width * window.frame.height)
            }
            .max {
                if $0.score != $1.score { return $0.score < $1.score }
                return $0.area < $1.area
            }?.window
    }

    private func captureImage(
        filter: SCContentFilter,
        width: Int,
        height: Int
    ) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
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
