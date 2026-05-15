//
//  AutoRecordingSettingsSections.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct AutoRecordingSettingsContent: View {
    @ObservedObject var viewModel: AutoRecordingSettingsViewModel
    @State private var isImporterPresented = false

    var body: some View {
        Group {
            Toggle("Enable auto recording", isOn: $viewModel.isEnabled)

            HStack {
                Text("Observed apps")
                Spacer()
                Button("Add App...") {
                    isImporterPresented = true
                }
                .buttonStyle(.bordered)
            }

            if viewModel.selectedApps.isEmpty {
                Text("No apps selected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.selectedApps, id: \.bundleIdentifier) { app in
                    HStack(alignment: .top, spacing: 16) {
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
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 2)
                }
            }

            Text("Recording starts when the microphone is active and any selected app is in use.")
                .font(.caption)
                .foregroundStyle(.secondary)

            inlineSliderRow(
                title: "Start delay",
                value: $viewModel.startDelay,
                range: 5 ... 20,
                step: 1
            )

            inlineSliderRow(
                title: "Stop delay",
                value: $viewModel.stopGracePeriod,
                range: 30 ... 120,
                step: 5
            )
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

    private func inlineSliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 90, alignment: .leading)

            Slider(value: value, in: range, step: step)

            Text("\(Int(value.wrappedValue))s")
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}
