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
            Section("Calendar Integration") {
                CalendarSettingsContent(viewModel: viewModel)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Calendar")
        .task {
            await viewModel.reload()
        }
    }
}

struct CalendarSettingsContent: View {
    @ObservedObject var viewModel: CalendarSettingsViewModel

    var body: some View {
        switch viewModel.authorizationState {
        case .authorized:
            calendarSelectionRow
            Text("QuickMeeting looks only at timed events for today and ignores all-day entries.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .notDetermined, .denied:
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

    private var calendarSelectionRow: some View {
        HStack(alignment: .top) {
            Text("Observed Calendars")

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Menu {
                    Button("Select All") {
                        viewModel.selectAllCalendars()
                    }

                    Button("Select None") {
                        viewModel.selectNoCalendars()
                    }

                    Divider()

                    ForEach(viewModel.availableCalendars) { calendar in
                        Button {
                            viewModel.toggleCalendarSelection(id: calendar.id)
                        } label: {
                            HStack {
                                Text(calendar.title)
                                Spacer()
                                if viewModel.selectedCalendarIDs.contains(calendar.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Select Calendars")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
                .menuStyle(.borderlessButton)

                Text(viewModel.selectedCalendarSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
