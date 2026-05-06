//
//  HomeView.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var appViewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Home")
                .font(.title2.weight(.semibold))

            Text(recordingStatusText(for: appViewModel.recordingState))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await appViewModel.startRecording()
                    }
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appViewModel.canStartRecording)

                Button {
                    Task {
                        await appViewModel.stopRecording()
                    }
                } label: {
                    Label("Stop Recording", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
                .disabled(!appViewModel.canStopRecording)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .navigationTitle("Home")
    }
}
