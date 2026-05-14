//
//  AutoRecordingSettingsSections.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import SwiftUI

struct AutoRecordingSettingsSections: View {
    @ObservedObject var viewModel: AutoRecordingSettingsViewModel

    var body: some View {
        Section("Auto Recording") {
            Toggle("Enable auto recording", isOn: $viewModel.isEnabled)
            Picker("Watched app", selection: $viewModel.selectedApp) {
                ForEach(AutoRecordingApp.allCases, id: \.self) { app in
                    Text(app.displayName).tag(app)
                }
            }

            HStack {
                Text("Start delay")
                Spacer()
                Text("\(Int(viewModel.startDelay))s")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $viewModel.startDelay, in: 5 ... 20, step: 1)

            HStack {
                Text("Stop grace period")
                Spacer()
                Text("\(Int(viewModel.stopGracePeriod))s")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $viewModel.stopGracePeriod, in: 30 ... 120, step: 5)
        }
        .onChange(of: viewModel.isEnabled) { _, _ in
            Task { await viewModel.save() }
        }
        .onChange(of: viewModel.selectedApp) { _, _ in
            Task { await viewModel.save() }
        }
        .onChange(of: viewModel.startDelay) { _, _ in
            Task { await viewModel.save() }
        }
        .onChange(of: viewModel.stopGracePeriod) { _, _ in
            Task { await viewModel.save() }
        }
    }
}
