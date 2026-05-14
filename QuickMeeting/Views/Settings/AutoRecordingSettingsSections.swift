//
//  AutoRecordingSettingsSections.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct AutoRecordingSettingsSections: View {
    @ObservedObject var viewModel: AutoRecordingSettingsViewModel
    @State private var isImporterPresented = false

    var body: some View {
        Section("Auto Recording") {
            Toggle("Enable auto recording", isOn: $viewModel.isEnabled)

            Button("Add App...") {
                isImporterPresented = true
            }

            if viewModel.selectedApps.isEmpty {
                Text("No apps selected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.selectedApps, id: \.bundleIdentifier) { app in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName)
                            Text(app.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            Task {
                                await viewModel.removeSelectedApp(bundleIdentifier: app.bundleIdentifier)
                            }
                        }
                    }
                }
            }

            Text("Recording starts when the microphone is active and any selected app is in use.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.application],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else {
                return
            }

            Task {
                try await viewModel.addSelectedApp(at: url)
            }
        }
        .onChange(of: viewModel.isEnabled) { _, _ in
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
