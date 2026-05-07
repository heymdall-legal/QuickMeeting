//
//  PersistedTranscriptSegment.swift
//  QuickMeeting
//
//  Created by Codex on 07.05.2026.
//

import Foundation
import SwiftData

@Model
final class PersistedTranscriptSegment {
    var id: UUID
    var text: String
    var startTime: TimeInterval?
    var endTime: TimeInterval?
    var speakerID: String?

    init(
        id: UUID,
        text: String,
        startTime: TimeInterval?,
        endTime: TimeInterval?,
        speakerID: String?
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speakerID = speakerID
    }

    convenience init(_ segment: TranscriptSegment) {
        self.init(
            id: segment.id,
            text: segment.text,
            startTime: segment.startTime,
            endTime: segment.endTime,
            speakerID: segment.speakerID
        )
    }

    var value: TranscriptSegment {
        TranscriptSegment(
            id: id,
            text: text,
            startTime: startTime,
            endTime: endTime,
            speakerID: speakerID
        )
    }
}
