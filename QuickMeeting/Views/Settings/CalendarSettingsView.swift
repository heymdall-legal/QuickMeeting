//
//  CalendarSettingsView.swift
//  QuickMeeting
//
//  Created by Codex on 08.05.2026.
//

import SwiftUI

struct CalendarSettingsView: View {
    @ObservedObject var viewModel: CalendarSettingsViewModel

    var body: some View {
        Form {
            CalendarSettingsSections(viewModel: viewModel)
        }
        .formStyle(.grouped)
        .navigationTitle("Calendar")
        .task {
            await viewModel.reload()
        }
    }
}

struct CalendarSettingsSections: View {
    @ObservedObject var viewModel: CalendarSettingsViewModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Use your macOS calendars")
                    .font(.title2.weight(.semibold))
                Text("QuickMeeting looks only at timed events for today and ignores all-day entries.")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }

        switch viewModel.authorizationState {
        case .authorized:
            Section("Calendars") {
                ForEach(viewModel.availableCalendars) { calendar in
                    Toggle(
                        calendar.title,
                        isOn: Binding(
                            get: { viewModel.selectedCalendarIDs.contains(calendar.id) },
                            set: { _ in
                                viewModel.toggleCalendarSelection(id: calendar.id)
                            }
                        )
                    )
                }
            }
        case .notDetermined, .denied:
            Section("Access") {
                Text("Allow calendar access, then choose which calendars Home uses to show the next event for today.")
                    .foregroundStyle(.secondary)

                Button("Grant Calendar Access") {
                    Task {
                        await viewModel.requestAccess()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
