//
//  SettingsView.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var calendarViewModel: CalendarSettingsViewModel
    @ObservedObject var autoRecordingViewModel: AutoRecordingSettingsViewModel
    @ObservedObject var huggingFaceTokenViewModel: HuggingFaceTokenSettingsViewModel

    var body: some View {
        Form {
            Section("Calendar Integration") {
                CalendarSettingsContent(viewModel: calendarViewModel)
            }

            Section("Auto Recording") {
                AutoRecordingSettingsContent(viewModel: autoRecordingViewModel)
            }

            Section("Transcription") {
                HuggingFaceTokenSettingsContent(viewModel: huggingFaceTokenViewModel)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 760, minHeight: 460)
        .navigationTitle("Settings")
        .task {
            await autoRecordingViewModel.load()
            await calendarViewModel.reload()
            await huggingFaceTokenViewModel.load()
        }
        .alert("Auto Recording App Error", isPresented: autoRecordingErrorIsPresented) {
            Button("OK") {
                autoRecordingViewModel.clearError()
            }
        } message: {
            Text(autoRecordingViewModel.errorMessage ?? "Unknown error.")
        }
    }

    private var autoRecordingErrorIsPresented: Binding<Bool> {
        Binding(
            get: { autoRecordingViewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    autoRecordingViewModel.clearError()
                }
            }
        )
    }
}
