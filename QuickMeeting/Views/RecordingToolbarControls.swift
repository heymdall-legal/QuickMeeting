//
//  RecordingToolbarControls.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import SwiftUI

struct RecordingToolbarControls: View {
    @ObservedObject var appViewModel: AppViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await appViewModel.startRecording()
                }
            } label: {
                Label("Start", systemImage: "record.circle")
            }
            .disabled(!appViewModel.canStartRecording)

            Button {
                Task {
                    await appViewModel.stopRecording()
                }
            } label: {
                Label("Stop", systemImage: "stop.circle")
            }
            .disabled(!appViewModel.canStopRecording)
        }
    }

    private var statusText: String {
        switch appViewModel.recordingState {
        case .idle:
            return "Ready"
        case .starting:
            return "Starting recording..."
        case .recording:
            return "Recording in progress"
        case .stopping:
            return "Stopping recording..."
        case .failed(let message):
            return message
        }
    }
}
