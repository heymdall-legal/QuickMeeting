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

            if let autoRecordingStatusText = appViewModel.autoRecordingStatusText {
                Text(autoRecordingStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let upcomingEvent = appViewModel.upcomingCalendarEvent {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next Event Today")
                        .font(.headline)
                    Text(upcomingEvent.title)
                        .font(.title3.weight(.semibold))
                    Text(eventTimeRange(for: upcomingEvent))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }

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
        .task {
            await appViewModel.loadUpcomingCalendarEvent()
        }
    }

    private func eventTimeRange(for event: UpcomingCalendarEvent) -> String {
        "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}
