//
//  PersistedTranscriptSpeaker.swift
//  QuickMeeting
//
//  Created by Codex on 07.05.2026.
//

import Foundation
import SwiftData

@Model
final class PersistedTranscriptSpeaker {
    var id: String
    var displayName: String

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    convenience init(_ speaker: TranscriptSpeaker) {
        self.init(id: speaker.id, displayName: speaker.displayName)
    }

    var value: TranscriptSpeaker {
        TranscriptSpeaker(id: id, displayName: displayName)
    }
}
