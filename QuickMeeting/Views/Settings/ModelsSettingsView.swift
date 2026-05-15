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
            Section("Transcription Models") {
                ModelsSettingsContent(
                    viewModel: viewModel,
                    pendingDeleteModelID: $pendingDeleteModelID
                )
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
}

struct ModelsSettingsContent: View {
    @ObservedObject var viewModel: ModelsSettingsViewModel
    @Binding var pendingDeleteModelID: TranscriptionModelID?

    var body: some View {
        if viewModel.isLoading {
            HStack {
                Text("Loading models...")
                Spacer()
                ProgressView()
                    .controlSize(.small)
            }
            .padding(.vertical, 6)
        } else {
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                modelRow(for: row)
                    .padding(.vertical, 8)

                if index < viewModel.rows.count - 1 {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(for row: TranscriptionModelRow) -> some View {
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

            VStack(alignment: .trailing, spacing: 8) {
                if case .downloading(let progress) = row.state {
                    ProgressView(value: progress)
                        .frame(width: 140)
                        .controlSize(.small)
                }

                HStack(spacing: 8) {
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

                        activationButton(for: row)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func activationButton(for row: TranscriptionModelRow) -> some View {
        if viewModel.defaultModelID == row.model.id {
            Button("Active") {}
                .buttonStyle(.borderedProminent)
                .tint(.green)
        } else {
            Button("Activate") {
                Task {
                    await viewModel.updateDefaultModel(row.model.id)
                    await viewModel.load()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private extension TranscriptionModelRow {
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
