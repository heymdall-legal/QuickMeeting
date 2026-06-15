//
//  MenuBarView.swift
//  QuickMeeting
//

import AppKit
import SwiftData
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var autoRecordingViewModel: AutoRecordingSettingsViewModel
    let onOpenMainWindow: () -> Void

    @Query(sort: \Meeting.startedAt, order: .reverse)
    private var allMeetings: [Meeting]

    @State private var recordingPulse = false

    private var recentMeetings: [Meeting] {
        allMeetings
            .filter { $0.id != viewModel.activeOrRecoverableMeetingID }
            .prefix(2)
            .map { $0 }
    }

    private var autoRecordAppNames: String {
        autoRecordingViewModel.selectedApps.map(\.displayName).joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.menuBarIconState {
            case .idle:             idlePanel()
            case .pendingAutoRecord: detectedPanel()
            case .recording:        recordingPanel()
            }
        }
        .frame(width: 320)
    }

    // MARK: - Idle

    @ViewBuilder
    private func idlePanel() -> some View {
        panelHeader {
            Text("Idle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(QMTheme.muted)
        }

        VStack(alignment: .leading, spacing: 0) {
            Button {
                Task { await viewModel.startRecording() }
            } label: {
                HStack(spacing: 9) {
                    Circle().fill(Color.white).frame(width: 9, height: 9)
                    Text("Start Recording")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(QMTheme.sage)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .shadow(color: QMTheme.sage.opacity(0.4), radius: 4, x: 0, y: 2)
            .disabled(!viewModel.canStartRecording)

            if autoRecordingViewModel.isEnabled && !autoRecordAppNames.isEmpty {
                HStack(spacing: 8) {
                    Circle().fill(QMTheme.sage).frame(width: 7, height: 7)
                    Text("Auto-record on")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(QMTheme.body)
                    Spacer()
                    Text(autoRecordAppNames)
                        .font(.system(size: 12.5))
                        .foregroundStyle(QMTheme.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 3)
                .padding(.top, 11)
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 2)
        .padding(.bottom, 13)

        panelDivider()

        if !recentMeetings.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("RECENT")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(QMTheme.muted)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 4)

                ForEach(recentMeetings) { meeting in
                    recentRow(meeting)
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 11)
            .padding(.bottom, 6)

            panelDivider().padding(.top, 4)
        }

        panelFooter {
            openMainWindowButton()
        } trailing: {
            settingsButton()
        }
    }

    // MARK: - Detected

    @ViewBuilder
    private func detectedPanel() -> some View {
        panelHeader {
            Text("Detected")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.44)
                .foregroundStyle(QMTheme.sage)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(QMTheme.sage.opacity(0.15))
                .clipShape(Capsule())
        }

        let appName = autoRecordingViewModel.selectedApps.first?.displayName ?? "App"
        let appInitial = String(appName.prefix(1))
        let meetingDesc = viewModel.upcomingCalendarEvent.map { "\"\($0.title)\" in progress" }
            ?? "Meeting in progress"

        HStack(spacing: 11) {
            Text(appInitial)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(QMTheme.sage)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text("\(appName) detected")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(QMTheme.ink)
                Text(meetingDesc)
                    .font(.system(size: 12))
                    .foregroundStyle(QMTheme.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(QMTheme.sage.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(QMTheme.sage.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .padding(.horizontal, 13)
        .padding(.top, 2)

        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            countdownSection()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)

        HStack(spacing: 9) {
            Button {
                Task { await viewModel.startRecording() }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(Color.white).frame(width: 8, height: 8)
                    Text("Start now")
                }
                .font(.system(size: 13.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(QMTheme.sage)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button("Not now") { }
                .buttonStyle(.plain)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(QMTheme.body)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 13)
        .padding(.bottom, 13)

        panelDivider()

        panelFooter {
            Text("Triggered by your watched apps")
                .font(.system(size: 12))
                .foregroundStyle(QMTheme.tertiary)
        } trailing: {
            Button("Adjust") { openSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(QMTheme.sage)
        }
    }

    @ViewBuilder
    private func countdownSection() -> some View {
        let remaining = countdownRemaining()
        let delay = autoRecordingViewModel.startDelay
        let progress: CGFloat = delay > 0 ? max(0, min(1, CGFloat(1 - remaining / delay))) : 1

        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Auto-recording in")
                    .font(.system(size: 13))
                    .foregroundStyle(QMTheme.body)
                Spacer()
                Text(remaining > 0 ? "\(Int(ceil(remaining)))s" : "Now")
                    .font(.system(size: 19, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(QMTheme.ink)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(QMTheme.sage)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 5)
        }
    }

    private func countdownRemaining() -> Double {
        guard let detectedAt = viewModel.autoRecordingDetectedAt else { return 0 }
        return max(0, autoRecordingViewModel.startDelay - Date().timeIntervalSince(detectedAt))
    }

    // MARK: - Recording

    @ViewBuilder
    private func recordingPanel() -> some View {
        panelHeader {
            HStack(spacing: 6) {
                Circle()
                    .fill(QMTheme.recording)
                    .frame(width: 7, height: 7)
                    .scaleEffect(recordingPulse ? 0.74 : 1.0)
                    .opacity(recordingPulse ? 0.4 : 0.95)
                    .animation(
                        .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                        value: recordingPulse
                    )
                Text("Recording")
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.44)
            }
            .foregroundStyle(QMTheme.recording)
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(QMTheme.recording.opacity(0.13))
            .clipShape(Capsule())
            .onAppear { recordingPulse = true }
            .onDisappear { recordingPulse = false }
        }

        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            liveBlock()
        }
        .padding(.horizontal, 13)
        .padding(.top, 2)

        Button {
            Task { await viewModel.stopRecording() }
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 11, height: 11)
                Text("Stop Recording")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(QMTheme.recording)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .shadow(color: QMTheme.recording.opacity(0.4), radius: 4, x: 0, y: 2)
        .disabled(!viewModel.canStopRecording)
        .padding(.horizontal, 13)
        .padding(.top, 13)
        .padding(.bottom, 13)

        panelDivider()

        panelFooter {
            openMainWindowButton()
        } trailing: {
            Text("Transcribes when you stop")
                .font(.system(size: 12))
                .foregroundStyle(QMTheme.muted)
        }
    }

    @ViewBuilder
    private func liveBlock() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.activeRecordingTitle ?? "Recording")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(QMTheme.ink)
                    .lineLimit(1)
                Spacer()
                Text(elapsedString())
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(QMTheme.ink)
                    .tracking(-0.22)
            }

            Text("Saving to Today")
                .font(.system(size: 12))
                .foregroundStyle(QMTheme.tertiary)

            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(waveformHeights.enumerated()), id: \.offset) { _, h in
                    Capsule()
                        .fill(QMTheme.sage)
                        .frame(width: 6, height: h)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .padding(.top, 12)
        }
        .padding(.horizontal, 15)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(Color.white.opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var waveformHeights: [CGFloat] {
        (0..<34).map { i in
            let base = abs(sin(Double(i) * 0.9)) * 0.64 + abs(cos(Double(i) * 0.5 + 1.0)) * 0.36
            return CGFloat(7.0 + base * 24.0)
        }
    }

    private func elapsedString() -> String {
        guard let startedAt = viewModel.recordingStartedAt else { return "0:00" }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    // MARK: - Shared components

    @ViewBuilder
    private func panelHeader<Badge: View>(@ViewBuilder badge: () -> Badge) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: MenuBarIconImageBuilder.waveformImage())
                .renderingMode(.template)
                .foregroundStyle(QMTheme.ink)
            Text("QuickMeeting")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(QMTheme.ink)
            Spacer()
            badge()
        }
        .padding(.horizontal, 15)
        .padding(.top, 13)
        .padding(.bottom, 11)
    }

    @ViewBuilder
    private func recentRow(_ meeting: Meeting) -> some View {
        let dotColor: Color = {
            let status = try? meeting.status
            switch status {
            case .completed:  return QMTheme.sage
            case .transcribing, .recorded: return QMTheme.transcribing
            default:          return QMTheme.recordedDot
            }
        }()

        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
            Text(meeting.title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(QMTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(relativeTime(from: meeting.startedAt))
                .font(.system(size: 11.5))
                .foregroundStyle(QMTheme.muted)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @ViewBuilder
    private func panelDivider() -> some View {
        Divider().padding(.horizontal, 13)
    }

    @ViewBuilder
    private func panelFooter<L: View, T: View>(
        @ViewBuilder leading: () -> L,
        @ViewBuilder trailing: () -> T
    ) -> some View {
        HStack {
            leading()
            Spacer()
            trailing()
        }
        .padding(.horizontal, 15)
        .padding(.top, 9)
        .padding(.bottom, 11)
    }

    @ViewBuilder
    private func openMainWindowButton() -> some View {
        Button("Open QuickMeeting") {
            onOpenMainWindow()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(QMTheme.sage)
    }

    @ViewBuilder
    private func settingsButton() -> some View {
        Button { openSettings() } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(QMTheme.tertiary)
        }
        .buttonStyle(.plain)
    }

    private func openSettings() {
        onOpenMainWindow()
        NotificationCenter.default.post(name: .qmOpenSettings, object: nil)
    }

    private func relativeTime(from date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            return f.string(from: date)
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: date)
        }
    }
}
