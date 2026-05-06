//
//  MenuBarView.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QuickMeeting")
                .font(.headline)

            Text(recordingStatusText(for: viewModel.recordingState))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(primaryActionTitle) {
                Task {
                    await performPrimaryAction()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canStartRecording && !viewModel.canStopRecording)
        }
        .padding(16)
        .frame(width: 220)
    }

    var primaryActionTitle: String {
        viewModel.canStartRecording ? "Start Recording" : "Stop Recording"
    }

    func performPrimaryAction() async {
        if viewModel.canStartRecording {
            await viewModel.startRecording()
        } else if viewModel.canStopRecording {
            await viewModel.stopRecording()
        }
    }
}
