//
//  HomeView.swift
//  QuickMeeting
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var autoRecordingViewModel: AutoRecordingSettingsViewModel
    let meetings: [Meeting]
    let onSelectMeeting: (UUID) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        if meetings.isEmpty {
            welcomeView
        } else {
            homeView
        }
    }

    // MARK: - Welcome (no recordings)

    private var welcomeView: some View {
        VStack(spacing: 0) {
            Spacer()

            Circle()
                .fill(QMTheme.sage)
                .frame(width: 72, height: 72)
                .overlay(Circle().fill(.white).frame(width: 22, height: 22))
                .shadow(color: QMTheme.sage.opacity(0.7), radius: 13, x: 0, y: 10)

            Text("Welcome to QuickMeeting")
                .font(.system(size: 25, weight: .bold))
                .tracking(-0.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(QMTheme.ink)
                .padding(.top, 22)
                .padding(.bottom, 11)

            Text("Record any meeting on your Mac and get a clean, speaker-by-speaker transcript — all on-device. Names come straight from your calendar.")
                .font(.system(size: 14.5))
                .lineSpacing(4)
                .foregroundStyle(QMTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 396)
                .padding(.bottom, 25)

            Button(action: { Task { await appViewModel.startRecording() } }) {
                HStack(spacing: 9) {
                    Circle().fill(.white).frame(width: 9, height: 9)
                    Text("Record your first meeting")
                        .font(.system(size: 14.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(QMTheme.sage, in: RoundedRectangle(cornerRadius: 11))
                .shadow(color: QMTheme.sage.opacity(0.4), radius: 5, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!appViewModel.canStartRecording)
            .opacity(appViewModel.canStartRecording ? 1 : 0.5)

            Button(action: onOpenSettings) {
                Text("or turn on auto-record →")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(QMTheme.sage)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(QMTheme.cardBorder)
                    .frame(height: 1)
                    .padding(.top, 44)

                HStack(alignment: .top, spacing: 14) {
                    featurePoint(
                        color: QMTheme.sage,
                        title: "On-device",
                        description: "Audio and transcripts never leave your Mac."
                    )
                    featurePoint(
                        color: QMTheme.recording,
                        title: "Auto-record",
                        description: "Starts itself when your meeting apps open."
                    )
                    featurePoint(
                        color: QMTheme.transcribing,
                        title: "Speaker names",
                        description: "Pulled from your calendar invites."
                    )
                }
                .frame(maxWidth: 520)
                .padding(.top, 30)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QMTheme.detailBackground)
    }

    private func featurePoint(color: Color, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .padding(.bottom, 9)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(QMTheme.ink)
                .padding(.bottom, 3)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(QMTheme.tertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Home (with recordings)

    private var homeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(todayLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(QMTheme.muted)

                Text(greeting)
                    .font(.system(size: 27, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(QMTheme.ink)
                    .padding(.top, 5)
                    .padding(.bottom, 24)

                recordCard

                if let jumpMeeting {
                    sectionHeader("Jump back in")
                        .padding(.top, 24)
                    jumpRow(jumpMeeting)
                }

                sectionHeader("Recent")
                    .padding(.top, 24)

                VStack(spacing: 7) {
                    ForEach(recentMeetings) { meeting in
                        recentRow(meeting)
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 36)
            .padding(.bottom, 44)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(QMTheme.detailBackground)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(QMTheme.muted)
            .padding(.bottom, 9)
    }

    private var recordCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start a recording")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                    Text("Capture and transcribe a meeting on this Mac.")
                        .font(.system(size: 13))
                        .foregroundStyle(QMTheme.tertiary)
                }
                Spacer(minLength: 0)
                Button(action: { Task { await appViewModel.startRecording() } }) {
                    HStack(spacing: 8) {
                        Circle().fill(.white).frame(width: 8, height: 8)
                        Text("Record")
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(QMTheme.sage, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: QMTheme.sage.opacity(0.4), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(!appViewModel.canStartRecording)
                .opacity(appViewModel.canStartRecording ? 1 : 0.5)
            }

            Rectangle()
                .fill(Color(hex: "#f0ebe1"))
                .frame(height: 1)
                .padding(.top, 16)

            Button(action: onOpenSettings) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(autoRecordingViewModel.isEnabled ? QMTheme.sage : QMTheme.recordedDot)
                        .frame(width: 8, height: 8)
                    Text(autoStatusText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(QMTheme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("Manage")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(QMTheme.sage)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 19)
        .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(QMTheme.cardBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.05), radius: 1.5, y: 1)
    }

    private func jumpRow(_ meeting: Meeting) -> some View {
        Button(action: { onSelectMeeting(meeting.id) }) {
            HStack(spacing: 13) {
                Circle()
                    .fill(dotColor(for: meeting))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                        .lineLimit(1)
                    Text(metaLabel(for: meeting))
                        .font(.system(size: 12.5))
                        .foregroundStyle(QMTheme.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(QMTheme.recordedDot)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(QMTheme.cardBorder, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.05), radius: 1.5, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recentRow(_ meeting: Meeting) -> some View {
        Button(action: { onSelectMeeting(meeting.id) }) {
            HStack(spacing: 12) {
                Circle()
                    .fill(dotColor(for: meeting))
                    .frame(width: 9, height: 9)
                Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(QMTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let label = statusLabel(for: meeting) {
                    Text(label)
                        .font(.system(size: 11.5))
                        .italic()
                        .foregroundStyle(QMTheme.tertiary)
                }
                Text(timeLabel(for: meeting))
                    .font(.system(size: 12))
                    .foregroundStyle(QMTheme.muted)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(QMTheme.cardBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed values

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var todayLabel: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var jumpMeeting: Meeting? {
        meetings.first(where: { (try? $0.status) == .recording })
            ?? meetings.first(where: { (try? $0.status) == .transcribing })
            ?? meetings.first
    }

    private var recentMeetings: [Meeting] {
        let jumpID = jumpMeeting?.id
        return Array(meetings.filter { $0.id != jumpID }.prefix(5))
    }

    private var autoStatusText: String {
        if autoRecordingViewModel.isEnabled {
            let names = autoRecordingViewModel.selectedApps.map(\.displayName)
            if names.isEmpty {
                return "Auto-record is on · no apps selected yet"
            }
            return "Auto-record is on · watching \(names.joined(separator: ", "))"
        }
        return "Auto-record is off · meetings won't capture automatically"
    }

    private func dotColor(for meeting: Meeting) -> Color {
        switch (try? meeting.status) ?? .completed {
        case .recording:   return QMTheme.recording
        case .transcribing: return QMTheme.transcribing
        case .recorded:    return QMTheme.recordedDot
        case .failed:      return QMTheme.faint
        case .completed:   return QMTheme.sage
        }
    }

    private func statusLabel(for meeting: Meeting) -> String? {
        switch (try? meeting.status) ?? .completed {
        case .recording:    return "Recording"
        case .transcribing: return "Transcribing"
        case .recorded:     return "Not transcribed"
        case .failed:       return "Failed"
        case .completed:    return nil
        }
    }

    private func metaLabel(for meeting: Meeting) -> String {
        switch (try? meeting.status) ?? .completed {
        case .recording:
            return "Recording now"
        case .transcribing:
            return "Transcribing now · \(timeLabel(for: meeting))"
        case .recorded:
            return "Not transcribed yet · \(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))"
        case .completed, .failed:
            let dateLabel = meeting.startedAt.formatted(date: .abbreviated, time: .shortened)
            if let duration = meeting.duration {
                return "\(dateLabel) · \(Int(duration / 60)) min"
            }
            return dateLabel
        }
    }

    private func timeLabel(for meeting: Meeting) -> String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInToday(meeting.startedAt) || calendar.isDateInYesterday(meeting.startedAt) {
            return meeting.startedAt.formatted(date: .omitted, time: .shortened)
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: meeting.startedAt), to: calendar.startOfDay(for: now)).day, days < 7 {
            return meeting.startedAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return meeting.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

