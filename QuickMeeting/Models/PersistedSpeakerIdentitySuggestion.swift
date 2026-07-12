//
//  PersistedSpeakerIdentitySuggestion.swift
//  QuickMeeting
//

import Foundation
import SwiftData

@Model
final class PersistedSpeakerIdentitySuggestion {
    @Attribute(.unique) var id: UUID
    var meetingID: UUID
    var speakerID: String
    var proposedName: String
    var confidenceRawValue: String
    var reason: String
    var evidenceImageRelativePath: String
    var evidenceThumbnailRelativePath: String?
    var observationID: UUID
    var capturedAtOffset: TimeInterval
    var statusRawValue: String

    init(_ value: SpeakerIdentitySuggestion) {
        id = value.id
        meetingID = value.meetingID
        speakerID = value.speakerID
        proposedName = value.proposedName
        confidenceRawValue = value.confidence.rawValue
        reason = value.reason
        evidenceImageRelativePath = value.evidenceImageRelativePath
        evidenceThumbnailRelativePath = value.evidenceThumbnailRelativePath
        observationID = value.observationID
        capturedAtOffset = value.capturedAtOffset
        statusRawValue = value.status.rawValue
    }

    var value: SpeakerIdentitySuggestion {
        SpeakerIdentitySuggestion(
            id: id,
            meetingID: meetingID,
            speakerID: speakerID,
            proposedName: proposedName,
            confidence: SpeakerIdentitySuggestionConfidence(rawValue: confidenceRawValue) ?? .low,
            reason: reason,
            evidenceImageRelativePath: evidenceImageRelativePath,
            evidenceThumbnailRelativePath: evidenceThumbnailRelativePath,
            observationID: observationID,
            capturedAtOffset: capturedAtOffset,
            status: SpeakerIdentitySuggestionStatus(rawValue: statusRawValue) ?? .pending
        )
    }
}
