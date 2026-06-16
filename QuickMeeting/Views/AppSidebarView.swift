//
//  AppSidebarView.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//  Redesigned to the "Direction 1" sidebar from QuickMeeting.dc.html.
//

import SwiftUI

struct AppSidebarView: View {
    @ObservedObject var appViewModel: AppViewModel
    let meetings: [Meeting]
    @Binding var selection: AppSidebarSelection
    let onOpenSettings: () -> Void

    @State private var searchText = ""
    @StateObject private var searchController = SidebarMeetingSearchController()

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            recordingsList
            settingsFooter
        }
        .background(QMTheme.sidebar)
        .navigationTitle("QuickMeeting")
        .onAppear {
            refreshSearchMeetings()
            refreshSearchQuery()
        }
        .onChange(of: searchIndexVersion) { _, _ in
            refreshSearchMeetings()
        }
        .onChange(of: searchText) { _, _ in
            refreshSearchQuery()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Recordings")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(QMTheme.ink)

            Spacer()

            Button(action: startRecording) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                    Text("Record")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(QMTheme.sage, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!appViewModel.canStartRecording)
            .opacity(appViewModel.canStartRecording ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(QMTheme.muted)
            TextField("Search recordings", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(QMTheme.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(QMTheme.searchField, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(QMTheme.fieldBorder, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Recordings

    private var recordingsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !meetings.isEmpty {
                    homeRow
                }

                if meetings.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedMeetings, id: \.title) { group in
                        Text(group.title.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.9)
                            .foregroundStyle(QMTheme.muted)
                            .padding(.horizontal, 8)
                            .padding(.top, 12)
                            .padding(.bottom, 6)

                        ForEach(group.meetings) { meeting in
                            recordingRow(meeting)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }

    private var homeRow: some View {
        let isSelected = selection == .home
        return Button {
            selection = .home
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "house")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(QMTheme.secondary)
                    .frame(width: 8)
                Text("Home")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(QMTheme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? QMTheme.selectedRow : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Text("No recordings yet")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(QMTheme.tertiary)
            Text("Your meetings will appear here once you start recording.")
                .font(.system(size: 12.5))
                .foregroundStyle(QMTheme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 18)
        .padding(.top, 44)
        .frame(maxWidth: .infinity)
    }

    private func recordingRow(_ meeting: Meeting) -> some View {
        let descriptor = statusDescriptor(for: meeting)
        let isSelected = selection == .meeting(meeting.id)

        return Button {
            selection = .meeting(meeting.id)
        } label: {
            HStack(alignment: .center, spacing: 9) {
                statusDot(descriptor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        Text(timeLabel(for: meeting))
                            .font(.system(size: 12))
                            .foregroundStyle(QMTheme.muted)
                        if let statusText = descriptor.statusText {
                            Text(statusText)
                                .font(.system(size: 11.5))
                                .italic()
                                .foregroundStyle(QMTheme.tertiary)
                        }
                    }

                    if descriptor.isTranscribing {
                        ProgressBar(progress: descriptor.progress, tint: QMTheme.transcribing)
                            .frame(height: 3)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? QMTheme.selectedRow : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusDot(_ descriptor: StatusDescriptor) -> some View {
        if descriptor.isActive {
            PulsingDot(color: QMTheme.recording, size: 8)
        } else {
            Circle()
                .fill(descriptor.dotColor)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: Settings footer

    private var settingsFooter: some View {
        Button {
            onOpenSettings()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(QMTheme.secondary)
                Text("Settings")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(QMTheme.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            QMTheme.sidebar
                .overlay(Rectangle().fill(QMTheme.hairline).frame(height: 1), alignment: .top)
        )
    }

    // MARK: Actions

    private func startRecording() {
        Task { await appViewModel.startRecording() }
    }

    private func refreshSearchMeetings() {
        searchController.replaceMeetings(meetings)
    }

    private func refreshSearchQuery() {
        searchController.updateQuery(searchText)
    }

    // MARK: Status

    private struct StatusDescriptor {
        var dotColor: Color = QMTheme.sage
        var statusText: String?
        var isActive = false
        var isTranscribing = false
        var progress: Double = 0
    }

    private func statusDescriptor(for meeting: Meeting) -> StatusDescriptor {
        switch (try? meeting.status) ?? .completed {
        case .recording:
            return StatusDescriptor(dotColor: QMTheme.recording, statusText: "Recording", isActive: true)
        case .transcribing:
            let progress = appViewModel.transcriptionProgress(for: meeting.id)
                ?? appViewModel.diarizationProgress(for: meeting.id)?.progress
                ?? 0.1
            return StatusDescriptor(
                dotColor: QMTheme.transcribing,
                statusText: "Transcribing",
                isTranscribing: true,
                progress: max(0.04, min(1, progress))
            )
        case .recorded:
            return StatusDescriptor(dotColor: QMTheme.recordedDot, statusText: "Not transcribed")
        case .failed:
            return StatusDescriptor(dotColor: QMTheme.faint, statusText: "Failed")
        case .completed:
            return StatusDescriptor(dotColor: QMTheme.sage)
        }
    }

    // MARK: Grouping

    private struct MeetingGroup {
        let title: String
        let meetings: [Meeting]
    }

    private struct SearchIndexVersion: Equatable {
        let id: UUID
        let updatedAt: Date
    }

    private var filteredMeetings: [Meeting] {
        guard !normalizedMeetingSearchQuery(searchText).isEmpty else {
            return meetings
        }

        return meetings.filter { searchController.matchingMeetingIDs.contains($0.id) }
    }

    private var searchIndexVersion: [SearchIndexVersion] {
        meetings.map { SearchIndexVersion(id: $0.id, updatedAt: $0.updatedAt) }
    }

    private var groupedMeetings: [MeetingGroup] {
        let calendar = Calendar.current
        let now = Date()
        let order = ["Today", "Yesterday", "Earlier This Week", "Earlier"]
        var buckets: [String: [Meeting]] = [:]

        for meeting in filteredMeetings {
            buckets[groupTitle(for: meeting.startedAt, calendar: calendar, now: now), default: []].append(meeting)
        }

        return order.compactMap { title in
            guard let items = buckets[title], !items.isEmpty else { return nil }
            return MeetingGroup(title: title, meetings: items)
        }
    }

    private func groupTitle(for date: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           days < 7 {
            return "Earlier This Week"
        }
        return "Earlier"
    }

    private func timeLabel(for meeting: Meeting) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(meeting.startedAt) || calendar.isDateInYesterday(meeting.startedAt) {
            return meeting.startedAt.formatted(date: .omitted, time: .shortened)
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: meeting.startedAt), to: Date()).day,
           days < 7 {
            return meeting.startedAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return meeting.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

/// A soft pulsing status dot for live recordings.
struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 8

    @State private var animating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(animating ? 0.82 : 1)
            .opacity(animating ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animating)
            .onAppear { animating = true }
    }
}

/// A thin rounded progress bar matching the design's transcribing indicator.
struct ProgressBar: View {
    let progress: Double
    var tint: Color = QMTheme.transcribing

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(QMTheme.fieldBorder)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, progress)) * proxy.size.width)
            }
        }
    }
}
