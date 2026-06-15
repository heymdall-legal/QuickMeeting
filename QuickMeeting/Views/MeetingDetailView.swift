//
//  MeetingDetailView.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//  Redesigned to the "Direction 3" transcript detail from QuickMeeting.dc.html
//  (speaker-tinted bubbles, no avatars, floating waveform player).
//

#if canImport(AppKit)
import AppKit
#endif
import SwiftUI

struct MeetingDetailView: View {
    let meeting: Meeting
    let transcriptionProgress: Double?
    let diarizationProgress: DiarizationProgressState?
    let canDelete: Bool
    let canTranscribe: Bool
    let transcriptionDisabledReason: String?
    let onTranscribe: () -> Void
    let onDelete: () -> Void
    let onStop: () -> Void
    let onRenameMeeting: (String) async throws -> Void
    let onRenameSpeaker: (String, String) -> Void

    @StateObject private var playback = MeetingAudioPlayback()
    @FocusState private var isMeetingTitleFocused: Bool
    @State private var transcriptContent: MeetingTranscriptContent = .notAvailable
    @State private var transcriptSpeakers = [TranscriptSpeaker]()
    /// The meeting whose transcript is currently reflected in `transcriptContent`.
    /// Until this matches the selected meeting, the detail shows a loading
    /// placeholder instead of the previously selected meeting's transcript.
    @State private var loadedMeetingID: UUID?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingRetranscriptionConfirmation = false
    @State private var meetingTitleDraft = ""
    @State private var originalMeetingTitle = ""
    @State private var isCommittingMeetingTitle = false
    @State private var renameOpenSegmentID: UUID?
    @State private var renameValue = ""
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?
    #if canImport(AppKit)
    @State private var hostWindow: NSWindow?
    #endif

    var body: some View {
        ZStack {
            QMTheme.detailBackground.ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let toastText {
                toast(toastText)
            }
        }
        .task(id: meetingTranscriptReloadKey(for: meeting)) {
            let transcript = meeting.storedTranscript
            transcriptContent = loadMeetingTranscriptContent(from: transcript)
            switch loadMeetingTranscriptSpeakers(from: transcript) {
            case .available(let speakers):
                transcriptSpeakers = speakers
            case .unavailable:
                transcriptSpeakers = []
            }
            loadedMeetingID = meeting.id
        }
        .task(id: meetingAudioReloadKey(for: meeting)) {
            await playback.loadAudioFileDeferred(at: URL(fileURLWithPath: meeting.audioFilePath))
        }
        .onAppear(perform: resetMeetingTitleDraft)
        .onChange(of: meeting.id) { _, _ in
            resetMeetingTitleDraft()
            renameOpenSegmentID = nil
            isMeetingTitleFocused = false
            #if canImport(AppKit)
            Task { @MainActor in
                clearMeetingDetailFocus(in: hostWindow)
            }
            #endif
        }
        .onChange(of: meeting.title) { _, newValue in
            guard !isMeetingTitleFocused, !isCommittingMeetingTitle else { return }
            meetingTitleDraft = newValue
            originalMeetingTitle = newValue
        }
        .onDisappear {
            toastTask?.cancel()
            toastTask = nil
        }
        .alert("Delete Meeting?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the meeting and its recording file from this Mac.")
        }
        .alert("Replace Transcript?", isPresented: $isShowingRetranscriptionConfirmation) {
            Button("Replace", role: .destructive, action: onTranscribe)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Starting transcription again will overwrite the existing transcript for this meeting.")
        }
        #if canImport(AppKit)
        .background(WindowReader(window: $hostWindow).frame(width: 0, height: 0))
        #endif
    }

    // MARK: Mode routing

    private enum DetailMode {
        case active
        case transcribing(activeStage: Int)
        case transcribed
        case recorded
        case loading
    }

    private var mode: DetailMode {
        if (try? meeting.status) == .recording {
            return .active
        }

        switch transcriptPaneState(
            hasTranscript: meeting.storedTranscript != nil,
            progress: transcriptionProgress,
            diarizationProgress: diarizationProgress
        ) {
        case .transcribing:
            return .transcribing(activeStage: 1)
        case .diarizing:
            return .transcribing(activeStage: 2)
        case .transcript:
            // The stored transcript hasn't been read into view state yet for
            // this meeting — show a placeholder instead of the previously
            // selected meeting's transcript while it loads.
            if loadedMeetingID != meeting.id {
                return .loading
            }
            if case .transcript = transcriptContent {
                return .transcribed
            }
            return .recorded
        case .empty:
            return .recorded
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .active:
            activeRecordingView
        case .transcribing(let activeStage):
            transcribingView(activeStage: activeStage)
        case .transcribed:
            transcribedView
        case .recorded:
            recordedView
        case .loading:
            transcriptLoadingView
        }
    }

    // MARK: Transcribed (hero)

    private var transcribedView: some View {
        VStack(spacing: 0) {
            transcribedHeader
            transcriptScroll
        }
        .overlay(alignment: .bottom) {
            WaveformPlayerBar(
                currentTime: playback.currentTime,
                duration: playback.duration,
                isPlaying: playback.state == .playing,
                isAvailable: playback.isPlaybackAvailable,
                onToggle: playback.togglePlayback,
                onSeek: seek(toFraction:)
            )
            .padding(.horizontal, 30)
            .padding(.bottom, 18)
        }
    }

    private var transcribedHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    meetingTitleField
                    Text(metaLabel)
                        .font(.system(size: 13.5))
                        .foregroundStyle(QMTheme.tertiary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    iconButton(systemName: "doc.on.doc", tint: QMTheme.secondary, help: "Copy transcript", action: copyTranscriptExport)
                    iconButton(systemName: "arrow.clockwise", tint: QMTheme.secondary, help: "Re-transcribe", action: handleTranscribeAction)
                    iconButton(systemName: "trash", tint: QMTheme.danger, help: "Delete") {
                        isShowingDeleteConfirmation = true
                    }
                    .disabled(!canDelete)
                }
            }

            if !attendeeChips.isEmpty {
                attendeeChipRow
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private var attendeeChipRow: some View {
        HFlow(spacing: 7, rowSpacing: 7) {
            ForEach(attendeeChips, id: \.name) { chip in
                HStack(spacing: 7) {
                    Circle().fill(chip.color).frame(width: 8, height: 8)
                    Text(chip.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(QMTheme.secondary)
                }
                .padding(.leading, 9)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .background(QMTheme.chip, in: Capsule())
            }
        }
    }

    private var transcriptScroll: some View {
        // A native List virtualizes rows (NSTableView-backed) so very long
        // transcripts stay smooth while scrolling. Rows are hosted in stable
        // table cells, so the per-row rename popover's anchor survives
        // re-renders — unlike a LazyVStack, which tears the anchored row down
        // on state change and dismisses the popover.
        List {
            ForEach(transcriptBubbles) { bubble in
                segmentBubble(bubble)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 5, leading: 30, bottom: 5, trailing: 30))
            }

            // Tail spacer so the last bubble can scroll clear of the floating
            // waveform player bar overlaid at the bottom.
            Color.clear
                .frame(height: 90)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.never)
    }

    private func segmentBubble(_ bubble: TranscriptBubble) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    openRename(segmentID: bubble.id, currentName: bubble.speakerName)
                } label: {
                    Text(bubble.speakerName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(bubble.style.color)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(QMTheme.faint).frame(height: 1).offset(y: 2)
                        }
                }
                .buttonStyle(.plain)
                .popover(isPresented: renameBinding(for: bubble.id), arrowEdge: .bottom) {
                    renamePopover(speakerID: bubble.speakerID)
                }

                Text(bubble.timeLabel)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(QMTheme.muted)

                if bubble.isUnnamed {
                    Button {
                        openRename(segmentID: bubble.id, currentName: bubble.speakerName)
                    } label: {
                        Text("· rename")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(QMTheme.sage)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }

            Text(bubble.text)
                .font(.system(size: 14.5))
                .lineSpacing(3)
                .foregroundStyle(QMTheme.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(bubble.style.tint, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(QMTheme.sage, lineWidth: bubble.isActive ? 2 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            if let start = bubble.startTime {
                seek(to: start)
            }
        }
    }

    // MARK: Rename popover

    private func renamePopover(speakerID: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("RENAME SPEAKER")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(QMTheme.muted)

            TextField("Speaker name", text: $renameValue)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(QMTheme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(QMTheme.sage, lineWidth: 1.5))
                .onSubmit { commitRename(speakerID: speakerID, name: renameValue) }

            let suggestions = renameSuggestions
            if suggestions.isEmpty {
                Text("No calendar matches — type a name above.")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(QMTheme.muted)
            } else {
                Text("Suggestions from calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(QMTheme.tertiary)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(suggestions, id: \.name) { suggestion in
                        Button {
                            commitRename(speakerID: speakerID, name: suggestion.name)
                        } label: {
                            HStack(spacing: 9) {
                                Circle().fill(suggestion.color).frame(width: 9, height: 9)
                                Text(suggestion.name)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(QMTheme.ink)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(13)
        .frame(width: 264)
        .background(QMTheme.card)
    }

    // MARK: Loading (transcript not yet read into view state)

    private var transcriptLoadingView: some View {
        VStack(spacing: 0) {
            simpleHeader(showDelete: false)

            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    SkeletonBubble(lineCount: index.isMultiple(of: 2) ? 3 : 2)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
    }

    // MARK: Recorded (not transcribed)

    private var recordedView: some View {
        VStack(spacing: 0) {
            simpleHeader(showDelete: true)

            WaveformPlayerBar(
                currentTime: playback.currentTime,
                duration: playback.duration,
                isPlaying: playback.state == .playing,
                isAvailable: playback.isPlaybackAvailable,
                onToggle: playback.togglePlayback,
                onSeek: seek(toFraction:)
            )
            .padding(.horizontal, 30)

            VStack(spacing: 0) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 24))
                    .foregroundStyle(QMTheme.faint)
                    .frame(width: 56, height: 56)
                    .background(QMTheme.chip, in: Circle())
                    .padding(.bottom, 18)

                Text("Not transcribed yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(QMTheme.ink)
                    .padding(.bottom, 6)

                Text("Transcribe this recording to get a speaker-by-speaker transcript and attendee names from your calendar.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(QMTheme.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .padding(.bottom, 20)

                Button(action: handleTranscribeAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                        Text("Transcribe")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(QMTheme.sage, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!canTranscribe)
                .opacity(canTranscribe ? 1 : 0.5)

                if let transcriptionDisabledReason {
                    Text(transcriptionDisabledReason)
                        .font(.system(size: 12))
                        .foregroundStyle(QMTheme.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
        }
    }

    // MARK: Transcribing stepper

    private func transcribingView(activeStage: Int) -> some View {
        VStack(spacing: 0) {
            simpleHeader(showDelete: false)

            VStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Transcribing…")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(QMTheme.ink)
                        .padding(.bottom, 4)
                    Text("This runs on-device. You can keep using the app.")
                        .font(.system(size: 13))
                        .foregroundStyle(QMTheme.tertiary)
                        .padding(.bottom, 18)

                    ShimmerBar()
                        .frame(height: 5)
                        .padding(.bottom, 22)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(stageLabels.enumerated()), id: \.offset) { index, label in
                            stageRow(label: label, index: index, activeStage: activeStage)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 26)
                .frame(width: 420)
                .background(QMTheme.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(QMTheme.cardBorder, lineWidth: 1))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
        }
    }

    private func stageRow(label: String, index: Int, activeStage: Int) -> some View {
        HStack(spacing: 12) {
            if index < activeStage {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(QMTheme.sage, in: Circle())
            } else if index == activeStage {
                SpinnerRing()
                    .frame(width: 20, height: 20)
            } else {
                Circle()
                    .strokeBorder(QMTheme.popoverBorder, lineWidth: 2)
                    .frame(width: 20, height: 20)
            }

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(index <= activeStage ? QMTheme.ink : QMTheme.muted)
        }
    }

    // MARK: Active recording

    private var activeRecordingView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PulsingDot(color: QMTheme.recording, size: 9)
                Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(QMTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 30)
            .padding(.top, 22)
            .padding(.bottom, 16)

            VStack(spacing: 0) {
                Text("RECORDING")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(QMTheme.recording)
                    .padding(.bottom, 18)

                LiveWaveform()
                    .frame(height: 90)
                    .padding(.bottom, 22)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(elapsedLabel)
                        .font(.system(size: 46, weight: .bold).monospacedDigit())
                        .foregroundStyle(QMTheme.ink)
                }
                .padding(.bottom, 26)

                Button(action: onStop) {
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 13, height: 13)
                        Text("Stop recording")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(QMTheme.recording, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
        }
    }

    // MARK: Shared header

    private func simpleHeader(showDelete: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                meetingTitleField
                Text(metaLabel)
                    .font(.system(size: 13.5))
                    .foregroundStyle(QMTheme.tertiary)
            }
            Spacer(minLength: 0)
            if showDelete {
                iconButton(systemName: "trash", tint: QMTheme.danger, help: "Delete") {
                    isShowingDeleteConfirmation = true
                }
                .disabled(!canDelete)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private var meetingTitleField: some View {
        TextField("Meeting title", text: $meetingTitleDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 23, weight: .bold))
            .foregroundStyle(QMTheme.ink)
            .focused($isMeetingTitleFocused)
            .onSubmit { commitMeetingRename(dismissFocus: true) }
            .onExitCommand(perform: cancelMeetingRename)
            .onChange(of: isMeetingTitleFocused) { _, isFocused in
                if !isFocused { commitMeetingRename(dismissFocus: false) }
            }
    }

    private func iconButton(systemName: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(QMTheme.card, in: Circle())
                .overlay(Circle().stroke(QMTheme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func toast(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(QMTheme.sidebar)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(QMTheme.ink, in: RoundedRectangle(cornerRadius: 11))
                .padding(.bottom, 28)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Derived data

    private struct TranscriptBubble: Identifiable {
        let id: UUID
        let speakerID: String
        let speakerName: String
        let style: QMSpeakerStyle
        let timeLabel: String
        let startTime: TimeInterval?
        let text: String
        let isUnnamed: Bool
        let isActive: Bool
    }

    private struct AttendeeChip { let name: String; let color: Color }
    private struct Suggestion { let name: String; let color: Color }

    private let stageLabels = ["Preparing audio", "Transcribing", "Diarizing speakers", "Finishing up"]

    private var attendeeChips: [AttendeeChip] {
        meeting.attendeeNames.map { AttendeeChip(name: $0, color: QMSpeakerPalette.style(for: $0).color) }
    }

    private var renameSuggestions: [Suggestion] {
        meeting.attendeeNames
            .filter { !QMSpeakerPalette.isUnnamed($0) }
            .map { Suggestion(name: $0, color: QMSpeakerPalette.style(for: $0).color) }
    }

    private var transcriptBubbles: [TranscriptBubble] {
        guard case .transcript(let display) = transcriptContent else { return [] }
        let speakersByID = Dictionary(uniqueKeysWithValues: display.speakers.map { ($0.id, $0.displayName) })
        let now = playback.currentTime

        return display.segments.enumerated().map { index, segment in
            let speakerID = segment.speakerID ?? "speaker-\(index)"
            let name = segment.speakerID.flatMap { speakersByID[$0] } ?? "Speaker \(index + 1)"
            let nextStart = display.segments[safe: index + 1]?.startTime
            let isActive: Bool = {
                guard now > 0, let start = segment.startTime else { return false }
                if let nextStart { return now >= start && now < nextStart }
                return now >= start
            }()

            return TranscriptBubble(
                id: segment.id,
                speakerID: speakerID,
                speakerName: name,
                style: QMSpeakerPalette.style(for: name, key: speakerID),
                timeLabel: segment.startTime.map(segmentTimestampText(for:)) ?? "",
                startTime: segment.startTime,
                text: segment.text,
                isUnnamed: QMSpeakerPalette.isUnnamed(name),
                isActive: isActive
            )
        }
    }

    private var metaLabel: String {
        var parts: [String] = []
        parts.append(meeting.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
        if let duration = meeting.duration {
            parts.append("\(Int((duration / 60).rounded())) min")
        }
        if !meeting.attendeeNames.isEmpty {
            parts.append(attendeeSummary)
        }
        return parts.joined(separator: " · ")
    }

    private var attendeeSummary: String {
        let names = meeting.attendeeNames.filter { !QMSpeakerPalette.isUnnamed($0) }
        guard !names.isEmpty else { return "" }
        if names.count == 1 { return names[0] }
        let firsts = names.map { $0.split(separator: " ").first.map(String.init) ?? $0 }
        return firsts.dropLast().joined(separator: ", ") + " & " + (firsts.last ?? "")
    }

    private var elapsedLabel: String {
        let elapsed = max(0, Int(Date().timeIntervalSince(meeting.startedAt)))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    // MARK: Actions

    private func seek(to time: TimeInterval) {
        playback.seek(to: time)
    }

    private func seek(toFraction fraction: Double) {
        playback.seek(to: fraction * playback.duration)
    }

    private func renameBinding(for segmentID: UUID) -> Binding<Bool> {
        Binding(
            get: { renameOpenSegmentID == segmentID },
            set: { isOpen in
                if !isOpen, renameOpenSegmentID == segmentID {
                    renameOpenSegmentID = nil
                }
            }
        )
    }

    private func openRename(segmentID: UUID, currentName: String) {
        renameValue = QMSpeakerPalette.isUnnamed(currentName) ? "" : currentName
        renameOpenSegmentID = segmentID
    }

    private func commitRename(speakerID: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        renameOpenSegmentID = nil
        guard !trimmed.isEmpty else { return }
        updateSpeakerName(trimmed, for: speakerID)
    }

    private func handleTranscribeAction() {
        if shouldConfirmRetranscription {
            isShowingRetranscriptionConfirmation = true
        } else {
            onTranscribe()
        }
    }

    private var shouldConfirmRetranscription: Bool {
        (try? meeting.status) == .completed
    }

    private func resetMeetingTitleDraft() {
        meetingTitleDraft = meeting.title
        originalMeetingTitle = meeting.title
        isCommittingMeetingTitle = false
    }

    private func commitMeetingRename(dismissFocus: Bool) {
        guard !isCommittingMeetingTitle else { return }

        let trimmedTitle = meetingTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty, trimmedTitle != originalMeetingTitle else {
            meetingTitleDraft = originalMeetingTitle
            if dismissFocus { isMeetingTitleFocused = false }
            return
        }

        let previousTitle = originalMeetingTitle
        isCommittingMeetingTitle = true

        Task {
            do {
                try await onRenameMeeting(trimmedTitle)
                await MainActor.run {
                    meetingTitleDraft = trimmedTitle
                    originalMeetingTitle = trimmedTitle
                    if dismissFocus { isMeetingTitleFocused = false }
                    isCommittingMeetingTitle = false
                }
            } catch {
                await MainActor.run {
                    meetingTitleDraft = previousTitle
                    originalMeetingTitle = previousTitle
                    if dismissFocus { isMeetingTitleFocused = false }
                    isCommittingMeetingTitle = false
                }
            }
        }
    }

    private func cancelMeetingRename() {
        guard !isCommittingMeetingTitle else { return }
        meetingTitleDraft = originalMeetingTitle
        isMeetingTitleFocused = false
    }

    private func updateSpeakerName(_ newValue: String, for speakerID: String) {
        if let index = transcriptSpeakers.firstIndex(where: { $0.id == speakerID }) {
            transcriptSpeakers[index].displayName = newValue
        }
        onRenameSpeaker(speakerID, newValue)
    }

    private func copyTranscriptExport() {
        guard let transcript = meeting.storedTranscript,
              isTranscriptExportAvailable(from: meeting.storedTranscript) else {
            return
        }

        let markdown = renderMeetingTranscriptExportMarkdown(meeting: meeting, transcript: transcript)

        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #endif

        showToast("Transcript copied to clipboard")
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { toastText = message }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) { toastText = nil }
                toastTask = nil
            }
        }
    }
}

// MARK: - Small animated pieces

/// A spinning ring used for the active transcription stage.
private struct SpinnerRing: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(QMTheme.sage, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .background(Circle().strokeBorder(QMTheme.fieldBorder, lineWidth: 2.5))
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

/// A placeholder transcript bubble shown while the stored transcript is being
/// read into view state, so a freshly opened meeting never flashes the
/// previously selected meeting's transcript.
private struct SkeletonBubble: View {
    let lineCount: Int
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(QMTheme.faint)
                .frame(width: 96, height: 12)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<lineCount, id: \.self) { line in
                    Capsule()
                        .fill(QMTheme.faint)
                        .frame(height: 11)
                        .frame(maxWidth: line == lineCount - 1 ? 220 : .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QMTheme.chip, in: RoundedRectangle(cornerRadius: 16))
        .opacity(pulsing ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
        .onAppear { pulsing = true }
    }
}

/// A sage shimmer sweeping across a track, for the transcribing card.
private struct ShimmerBar: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(QMTheme.searchField)
                .overlay(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [QMTheme.sage.opacity(0), QMTheme.sage, QMTheme.sage.opacity(0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * 0.4)
                        .offset(x: phase * proxy.size.width)
                )
                .clipShape(Capsule())
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1.2
                    }
                }
        }
    }
}

/// The animated sage bars shown while a recording is live.
private struct LiveWaveform: View {
    private let count = 44

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { index in
                    let phase = Double(index) * 0.5
                    let scale = 0.3 + 0.7 * abs(sin(t * 3 + phase))
                    Capsule()
                        .fill(QMTheme.sage)
                        .frame(width: 4, height: 70 * scale)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// A simple left-aligned wrapping flow layout for chips.
struct HFlow: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + rowSpacing
                maxRowWidth = max(maxRowWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        maxRowWidth = max(maxRowWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxRowWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
