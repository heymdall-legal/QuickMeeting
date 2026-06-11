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
    case diarizing(DiarizationProgressState)
    case transcript
}

func transcriptPaneState(
    hasTranscript: Bool,
    progress: Double?,
    diarizationProgress: DiarizationProgressState?
) -> TranscriptPaneState {
    if let diarizationProgress {
        return .diarizing(
            DiarizationProgressState(
                progress: min(max(diarizationProgress.progress, 0), 1),
                stepName: diarizationProgress.stepName
            )
        )
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

func diarizationProgressTitle(stepName: String?) -> String {
    guard let stepName else {
        return "Diarization..."
    }

    let trimmed = stepName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return "Diarization..."
    }

    let separated = trimmed
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")

    return "\(separated.localizedCapitalized)..."
}
