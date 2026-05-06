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
    case transcriptFile(String)
}

func transcriptPaneState(
    meetingStatus: MeetingStatus,
    transcriptFilePath: String?,
    progress: Double?,
    diarizationProgress: Double?
) -> TranscriptPaneState {
    if meetingStatus == .transcribing {
        if let diarizationProgress {
            return .diarizing(progress: min(max(diarizationProgress, 0), 1))
        }
        if let progress {
            return .transcribing(progress: min(max(progress, 0), 1))
        }
    }

    if let transcriptFilePath {
        return .transcriptFile(transcriptFilePath)
    }

    return .empty
}

func transcriptionProgressText(_ progress: Double) -> String {
    "\(Int(min(max(progress, 0), 1) * 100))% complete"
}

func diarizationProgressText(_ progress: Double) -> String {
    "\(Int(min(max(progress, 0), 1) * 100))% complete"
}
