//
//  ScreenObservation.swift
//  QuickMeeting
//

import Foundation

nonisolated struct UnitRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    func contains(centerOf other: UnitRect) -> Bool {
        let centerX = other.x + other.width / 2
        let centerY = other.y + other.height / 2
        return centerX >= x && centerX <= x + width
            && centerY >= y && centerY <= y + height
    }
}

nonisolated struct ScreenTextObservation: Codable, Equatable, Sendable {
    let text: String
    let boundingBox: UnitRect
}

nonisolated struct ScreenTileObservation: Codable, Equatable, Sendable {
    let boundingBox: UnitRect
    let matchedName: String?
    let highlightScore: Double
}

nonisolated struct ScreenObservation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let meetingID: UUID
    let capturedAtOffset: TimeInterval
    let imageRelativePath: String
    let thumbnailRelativePath: String?
    let sourceAppBundleID: String?
    let sourceWindowTitle: String?
    let textBoxes: [ScreenTextObservation]
    let activeTile: ScreenTileObservation?

    init(
        id: UUID = UUID(),
        meetingID: UUID,
        capturedAtOffset: TimeInterval,
        imageRelativePath: String,
        thumbnailRelativePath: String?,
        sourceAppBundleID: String? = nil,
        sourceWindowTitle: String? = nil,
        textBoxes: [ScreenTextObservation] = [],
        activeTile: ScreenTileObservation? = nil
    ) {
        self.id = id
        self.meetingID = meetingID
        self.capturedAtOffset = capturedAtOffset
        self.imageRelativePath = imageRelativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceWindowTitle = sourceWindowTitle
        self.textBoxes = textBoxes
        self.activeTile = activeTile
    }
}

nonisolated enum SpeakerIdentitySuggestionConfidence: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

nonisolated enum SpeakerIdentitySuggestionStatus: String, Codable, Equatable, Sendable {
    case pending
    case accepted
    case dismissed
    case superseded
}

nonisolated struct SpeakerIdentitySuggestionKey: Hashable, Sendable {
    let speakerID: String
    let proposedName: String
}

nonisolated struct SpeakerIdentitySuggestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let meetingID: UUID
    let speakerID: String
    let proposedName: String
    let confidence: SpeakerIdentitySuggestionConfidence
    let reason: String
    let evidenceImageRelativePath: String
    let evidenceThumbnailRelativePath: String?
    let observationID: UUID
    let capturedAtOffset: TimeInterval
    let status: SpeakerIdentitySuggestionStatus

    init(
        id: UUID = UUID(),
        meetingID: UUID,
        speakerID: String,
        proposedName: String,
        confidence: SpeakerIdentitySuggestionConfidence,
        reason: String,
        evidenceImageRelativePath: String,
        evidenceThumbnailRelativePath: String?,
        observationID: UUID,
        capturedAtOffset: TimeInterval,
        status: SpeakerIdentitySuggestionStatus = .pending
    ) {
        self.id = id
        self.meetingID = meetingID
        self.speakerID = speakerID
        self.proposedName = proposedName
        self.confidence = confidence
        self.reason = reason
        self.evidenceImageRelativePath = evidenceImageRelativePath
        self.evidenceThumbnailRelativePath = evidenceThumbnailRelativePath
        self.observationID = observationID
        self.capturedAtOffset = capturedAtOffset
        self.status = status
    }

    var key: SpeakerIdentitySuggestionKey {
        SpeakerIdentitySuggestionKey(speakerID: speakerID, proposedName: proposedName)
    }
}
