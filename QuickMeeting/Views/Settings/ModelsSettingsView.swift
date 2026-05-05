//
//  ModelsSettingsView.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var viewModel: ModelsSettingsViewModel

    @State private var pendingDeleteModelID: TranscriptionModelID?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Manage on-device transcription models")
                        .font(.title2.weight(.semibold))
                    Text("Downloads only start when you click them. Choose a default model once you have one installed.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Default Model") {
                Picker("Model", selection: defaultModelSelection) {
                    Text(installedRows.isEmpty ? "No installed models" : "None")
                        .tag(Optional<TranscriptionModelID>.none)

                    ForEach(installedRows) { row in
                        Text(row.model.displayName)
                            .tag(Optional(row.model.id))
                    }
                }
                .disabled(installedRows.isEmpty)
            }

            Section("Available Models") {
                ForEach(viewModel.rows) { row in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.model.displayName)
                                .font(.headline)
                            Text(row.model.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(row.stateDescription)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer(minLength: 20)

                        if case .downloading(let progress) = row.state {
                            ProgressView(value: progress)
                                .frame(width: 120)
                                .controlSize(.small)
                        }

                        actionButton(for: row)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await viewModel.load()
        }
        .alert("Model Operation Failed", isPresented: errorIsPresented) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error.")
        }
        .confirmationDialog(
            "Delete downloaded model?",
            isPresented: deleteDialogIsPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let pendingDeleteModelID else {
                    return
                }

                Task {
                    await viewModel.delete(pendingDeleteModelID)
                    self.pendingDeleteModelID = nil
                }
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteModelID = nil
            }
        } message: {
            Text("The downloaded model files will be removed from QuickMeeting storage.")
        }
    }

    private var installedRows: [TranscriptionModelRow] {
        viewModel.rows.filter(\.isInstalled)
    }

    private var defaultModelSelection: Binding<TranscriptionModelID?> {
        Binding(
            get: { viewModel.defaultModelID },
            set: { newValue in
                Task {
                    await viewModel.updateDefaultModel(newValue)
                    await viewModel.load()
                }
            }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.clearError()
                }
            }
        )
    }

    private var deleteDialogIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteModelID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteModelID = nil
                }
            }
        )
    }

    @ViewBuilder
    private func actionButton(for row: TranscriptionModelRow) -> some View {
        switch row.state {
        case .notInstalled, .failed:
            Button("Download") {
                Task {
                    await viewModel.download(row.model.id)
                }
            }
            .buttonStyle(.borderedProminent)
        case .downloading:
            Button("Downloading") {}
                .buttonStyle(.bordered)
                .disabled(true)
        case .installed:
            Button("Delete", role: .destructive) {
                pendingDeleteModelID = row.model.id
            }
            .buttonStyle(.bordered)
        }
    }
}

private extension TranscriptionModelRow {
    var isInstalled: Bool {
        if case .installed = state {
            return true
        }

        return false
    }

    var stateDescription: String {
        switch state {
        case .notInstalled:
            return "Not installed"
        case .downloading(let progress):
            if let progress {
                return "\(Int(progress * 100))% downloaded"
            }

            return "Downloading"
        case .installed(let sizeInBytes, _):
            return ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
        case .failed(let message):
            return message
        }
    }
}
