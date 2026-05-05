//
//  MeetingListView.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import SwiftUI

struct MeetingListView: View {
    let meetings: [Meeting]
    @Binding var selection: UUID?

    var body: some View {
        List(meetings, selection: $selection) { meeting in
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                    .font(.headline)

                Text(meeting.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(meeting.id)
        }
    }
}
