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
    var sortIndex: Int?

    init(
        id: UUID,
        text: String,
        startTime: TimeInterval?,
        endTime: TimeInterval?,
        speakerID: String?,
        sortIndex: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speakerID = speakerID
        self.sortIndex = sortIndex
    }

    convenience init(_ segment: TranscriptSegment) {
        self.init(segment, sortIndex: nil)
    }

    convenience init(_ segment: TranscriptSegment, sortIndex: Int?) {
        self.init(
            id: segment.id,
            text: segment.text,
            startTime: segment.startTime,
            endTime: segment.endTime,
            speakerID: segment.speakerID,
            sortIndex: sortIndex
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
