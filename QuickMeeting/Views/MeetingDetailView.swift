//
//  MeetingDetailView.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import SwiftUI

struct MeetingDetailView: View {
    let meeting: Meeting
    let canDelete: Bool
    let onDelete: () -> Void

    @StateObject private var playback = MeetingAudioPlayback()
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                LabeledContent("Status", value: statusText)
                LabeledContent(
                    "Started",
                    value: meeting.startedAt.formatted(
                        .dateTime.month(.wide).day().year().hour().minute()
                    )
                )

                if let endedAt = meeting.endedAt {
                    LabeledContent(
                        "Ended",
                        value: endedAt.formatted(
                            .dateTime.month(.wide).day().year().hour().minute()
                        )
                    )
                }

                if let duration = meeting.duration {
                    LabeledContent("Duration", value: durationText(duration))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio Playback")
                        .font(.headline)

                    Button(action: playback.togglePlayback) {
                        Label(playbackButtonTitle, systemImage: playbackButtonSystemImage)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!playback.isPlaybackAvailable)

                    Text(playback.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Audio File")
                        .font(.headline)
                    Text(meeting.audioFilePath)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Delete Meeting", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .disabled(!canDelete)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .navigationTitle(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
        .task(id: meeting.id) {
            try? playback.loadAudioFile(at: URL(fileURLWithPath: meeting.audioFilePath))
        }
        .alert(
            "Delete Meeting?",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the meeting and its recording file from this Mac.")
        }
    }

    private var statusText: String {
        guard let status = try? meeting.status else {
            return "Invalid Status"
        }

        switch status {
        case .recording:
            return "Recording"
        case .recorded:
            return "Recorded"
        case .transcribing:
            return "Transcribing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3_600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: duration) ?? "\(Int(duration)) sec"
    }

    private var playbackButtonTitle: String {
        switch playback.state {
        case .playing:
            return "Pause"
        default:
            return "Play"
        }
    }

    private var playbackButtonSystemImage: String {
        switch playback.state {
        case .playing:
            return "pause.fill"
        default:
            return "play.fill"
        }
    }
}
