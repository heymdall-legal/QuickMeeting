//
//  AppSidebarView.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import SwiftUI

struct AppSidebarView: View {
    let meetings: [Meeting]
    @Binding var selection: AppSidebarSelection

    var body: some View {
        List(selection: listSelection) {
            Section {
                Label("Home", systemImage: "house")
                    .tag(AppSidebarSelection.home)

                Label("Settings", systemImage: "gearshape")
                    .tag(AppSidebarSelection.settings)
            }

            Section("History") {
                ForEach(meetings) { meeting in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                            .font(.headline)

                        Text(meeting.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(AppSidebarSelection.meeting(meeting.id))
                }
            }
        }
        .navigationTitle("QuickMeeting")
    }

    private var listSelection: Binding<AppSidebarSelection?> {
        Binding(
            get: { selection },
            set: { newValue in
                guard let newValue else {
                    return
                }

                selection = newValue
            }
        )
    }
}
