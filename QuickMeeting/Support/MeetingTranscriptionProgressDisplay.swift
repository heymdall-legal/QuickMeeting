//
//  MeetingTranscriptionProgressDisplay.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation

enum TranscriptPaneState: Equatable {
    case empty
    case transcribing(progress: Double)
    case diarizing(progress: Double)
    case transcript
}

func transcriptPaneState(
    hasTranscript: Bool,
    progress: Double?,
    diarizationProgress: Double?
) -> TranscriptPaneState {
    if let diarizationProgress {
        return .diarizing(progress: min(max(diarizationProgress, 0), 1))
    }
    if let progress {
        return .transcribing(progress: min(max(progress, 0), 1))
    }

    if hasTranscript {
        return .transcript
    }

    return .empty
}

func transcriptionProgressText(_ progress: Double) -> String {
    "\(Int(min(max(progress, 0), 1) * 100))% complete"
}

func diarizationProgressText(_ progress: Double) -> String {
    "\(Int(min(max(progress, 0), 1) * 100))% complete"
}
