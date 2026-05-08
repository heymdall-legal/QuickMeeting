//
//  SettingsView.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var modelsViewModel: ModelsSettingsViewModel
    @ObservedObject var calendarViewModel: CalendarSettingsViewModel
    @State private var pendingDeleteModelID: TranscriptionModelID?

    var body: some View {
        Form {
            CalendarSettingsSections(viewModel: calendarViewModel)
            ModelsSettingsSections(
                viewModel: modelsViewModel,
                pendingDeleteModelID: $pendingDeleteModelID
            )
        }
        .formStyle(.grouped)
        .frame(minWidth: 760, minHeight: 460)
        .navigationTitle("Settings")
        .task {
            await calendarViewModel.reload()
            await modelsViewModel.load()
        }
        .alert("Model Operation Failed", isPresented: modelErrorIsPresented) {
            Button("OK") {
                modelsViewModel.clearError()
            }
        } message: {
            Text(modelsViewModel.errorMessage ?? "Unknown error.")
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
                    await modelsViewModel.delete(pendingDeleteModelID)
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

    private var modelErrorIsPresented: Binding<Bool> {
        Binding(
            get: { modelsViewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    modelsViewModel.clearError()
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
