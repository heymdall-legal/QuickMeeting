//
//  MeetingDetailView.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

#if canImport(AppKit)
import AppKit
#endif
import SwiftUI

struct MeetingDetailView: View {
    let meeting: Meeting
    let transcriptionProgress: Double?
    let diarizationProgress: Double?
    let canDelete: Bool
    let canTranscribe: Bool
    let onTranscribe: () -> Void
    let onDelete: () -> Void
    let onRenameMeeting: (String) async throws -> Void
    let onRenameSpeaker: (String, String) -> Void

    @StateObject private var playback = MeetingAudioPlayback()
    @FocusState private var isMeetingTitleFocused: Bool
    @State private var transcriptContent: MeetingTranscriptContent = .notAvailable
    @State private var transcriptSpeakers = [TranscriptSpeaker]()
    @State private var showSegmentTimes = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingRetranscriptionConfirmation = false
    @State private var meetingTitleDraft = ""
    @State private var originalMeetingTitle = ""
    @State private var isCommittingMeetingTitle = false
    @State private var exportFeedbackText: String?
    @State private var exportFeedbackTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                transcriptPane

                Divider()

                sidebar
                    .frame(width: 300)
            }

            Divider()

            playbackBar
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.background)
        }
        .navigationTitle(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
        .task(id: meetingTranscriptReloadKey(for: meeting)) {
            let transcript = meeting.storedTranscript
            transcriptContent = loadMeetingTranscriptContent(from: transcript)
            switch loadMeetingTranscriptSpeakers(from: transcript) {
            case .available(let speakers):
                transcriptSpeakers = speakers
            case .unavailable:
                transcriptSpeakers = []
            }
        }
        .task(id: meetingAudioReloadKey(for: meeting)) {
            await playback.loadAudioFileDeferred(at: URL(fileURLWithPath: meeting.audioFilePath))
        }
        .onAppear(perform: resetMeetingTitleDraft)
        .onChange(of: meeting.id) { _, _ in
            resetMeetingTitleDraft()
        }
        .onChange(of: meeting.title) { _, newValue in
            guard !isMeetingTitleFocused, !isCommittingMeetingTitle else {
                return
            }

            meetingTitleDraft = newValue
            originalMeetingTitle = newValue
        }
        .onDisappear {
            exportFeedbackTask?.cancel()
            exportFeedbackTask = nil
        }
        .alert(
            "Delete Meeting?",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the meeting and its recording file from this Mac.")
        }
        .alert(
            "Replace Transcript?",
            isPresented: $isShowingRetranscriptionConfirmation
        ) {
            Button("Replace", role: .destructive) {
                onTranscribe()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Starting transcription again will overwrite the existing transcript for this meeting.")
        }
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch currentTranscriptPaneState {
            case .empty:
                transcriptEmptyState
            case .transcribing(let progress):
                transcriptionProgressState(progress: progress)
            case .diarizing(let progress):
                diarizationProgressState(progress: progress)
            case .transcript:
                switch transcriptContent {
                case .transcript(let display):
                    TranscriptTextView(display: display, showSegmentTimes: showSegmentTimes)
                case .notAvailable:
                    transcriptEmptyState
                case .unavailable(let message):
                    transcriptUnavailableState(message: message)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }

    private var currentTranscriptPaneState: TranscriptPaneState {
        transcriptPaneState(
            meetingStatus: (try? meeting.status) ?? .recorded,
            hasTranscript: meeting.storedTranscript != nil,
            progress: transcriptionProgress,
            diarizationProgress: diarizationProgress
        )
    }

    private var transcriptEmptyState: some View {
        VStack(spacing: 12) {
            Text("Not transcribed yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Meeting audio is available and can be transcribed when you're ready.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Transcribe", action: handleTranscribeAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canTranscribe)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcriptUnavailableState(message: String) -> some View {
        VStack(spacing: 12) {
            Text("Transcript unavailable")
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Transcribe", action: handleTranscribeAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canTranscribe)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcriptionProgressState(progress: Double) -> some View {
        VStack(spacing: 12) {
            Text("Transcribing...")
                .font(.title3)
                .fontWeight(.semibold)

            ProgressView(value: progress)
                .frame(maxWidth: 280)

            Text(transcriptionProgressText(progress))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func diarizationProgressState(progress: Double) -> some View {
        VStack(spacing: 12) {
            Text("Diarization")
                .font(.title3)
                .fontWeight(.semibold)

            ProgressView(value: progress)
                .frame(maxWidth: 280)

            Text(diarizationProgressText(progress))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                detailSection
                transcriptDisplaySection
                actionSection
                speakersSection
                filesSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            meetingTitleField

            Text("Details")
                .font(.headline)

            LabeledContent("Status", value: statusText)
            LabeledContent(
                "Started",
                value: meeting.startedAt.formatted(
                    .dateTime.month(.wide).day().year().hour().minute()
                )
            )

            if let endedAt = meeting.endedAt {
                LabeledContent(
                    "Ended",
                    value: endedAt.formatted(
                        .dateTime.month(.wide).day().year().hour().minute()
                    )
                )
            }

            if let duration = meeting.duration {
                LabeledContent("Duration", value: durationText(duration))
            }
        }
    }

    private var meetingTitleField: some View {
        TextField("Meeting title", text: $meetingTitleDraft)
            .textFieldStyle(.roundedBorder)
            .font(.title2.weight(.semibold))
            .focused($isMeetingTitleFocused)
            .onSubmit {
                commitMeetingRename(dismissFocus: true)
            }
            .onExitCommand(perform: cancelMeetingRename)
            .onChange(of: isMeetingTitleFocused) { _, isFocused in
                if !isFocused {
                    commitMeetingRename(dismissFocus: false)
                }
            }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.headline)

            Button("Transcribe", action: handleTranscribeAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canTranscribe)

            if isTranscriptExportAvailable(from: meeting.storedTranscript) {
                HStack(spacing: 10) {
                    Button("Export Transcript", action: copyTranscriptExport)

                    if let exportFeedbackText {
                        Text(exportFeedbackText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button("Delete Meeting", role: .destructive) {
                isShowingDeleteConfirmation = true
            }
            .disabled(!canDelete)
        }
    }

    private var transcriptDisplaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcript Display")
                .font(.headline)

            Toggle("Show segment times", isOn: $showSegmentTimes)
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Files")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Audio File")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(meeting.audioFilePath)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var speakersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Speakers")
                .font(.headline)

            if transcriptSpeakers.isEmpty {
                Text("Speaker data unavailable")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(transcriptSpeakers) { speaker in
                    SpeakerNameInput(
                        displayName: resolvedDisplayName(for: speaker.id),
                        attendeeNames: meeting.attendeeNames
                    ) { newValue in
                        updateSpeakerName(newValue, for: speaker.id)
                    }
                }
            }
        }
    }

    private var playbackBar: some View {
        HStack(spacing: 16) {
            Button(action: playback.togglePlayback) {
                Image(systemName: playbackButtonSystemImage)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!playback.isPlaybackAvailable)
            .help(playback.statusText)

            VStack(alignment: .leading, spacing: 6) {
                Slider(
                    value: Binding(
                        get: { playback.currentTime },
                        set: { playback.seek(to: $0) }
                    ),
                    in: 0...max(playback.duration, 0.1)
                )
                .disabled(!playback.isPlaybackAvailable)

                if !playback.isPlaybackAvailable {
                    Text(playback.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(playback.elapsedTimeText) / \(playback.durationText)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 92, alignment: .trailing)
        }
    }

    private func handleTranscribeAction() {
        if shouldConfirmRetranscription {
            isShowingRetranscriptionConfirmation = true
        } else {
            onTranscribe()
        }
    }

    private var shouldConfirmRetranscription: Bool {
        guard let status = try? meeting.status else {
            return false
        }

        return status == .completed
    }

    private var statusText: String {
        guard let status = try? meeting.status else {
            return "Invalid Status"
        }

        switch status {
        case .recording:
            return "Recording"
        case .recorded:
            return "Recorded"
        case .transcribing:
            return "Transcribing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3_600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: duration) ?? "\(Int(duration)) sec"
    }

    private var playbackButtonSystemImage: String {
        switch playback.state {
        case .playing:
            return "pause.fill"
        default:
            return "play.fill"
        }
    }

    private func resolvedDisplayName(for speakerID: String) -> String {
        transcriptSpeakers.first(where: { $0.id == speakerID })?.displayName ?? ""
    }

    private func resetMeetingTitleDraft() {
        meetingTitleDraft = meeting.title
        originalMeetingTitle = meeting.title
        isCommittingMeetingTitle = false
    }

    private func commitMeetingRename(dismissFocus: Bool) {
        guard !isCommittingMeetingTitle else {
            return
        }

        let trimmedTitle = meetingTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            meetingTitleDraft = originalMeetingTitle
            if dismissFocus {
                isMeetingTitleFocused = false
            }
            return
        }

        guard trimmedTitle != originalMeetingTitle else {
            meetingTitleDraft = originalMeetingTitle
            if dismissFocus {
                isMeetingTitleFocused = false
            }
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
                    if dismissFocus {
                        isMeetingTitleFocused = false
                    }
                    isCommittingMeetingTitle = false
                }
            } catch {
                await MainActor.run {
                    meetingTitleDraft = previousTitle
                    originalMeetingTitle = previousTitle
                    if dismissFocus {
                        isMeetingTitleFocused = false
                    }
                    isCommittingMeetingTitle = false
                }
            }
        }
    }

    private func cancelMeetingRename() {
        guard !isCommittingMeetingTitle else {
            return
        }

        meetingTitleDraft = originalMeetingTitle
        isMeetingTitleFocused = false
    }

    private func updateSpeakerName(_ newValue: String, for speakerID: String) {
        guard let speakerIndex = transcriptSpeakers.firstIndex(where: { $0.id == speakerID }) else {
            return
        }

        transcriptSpeakers[speakerIndex].displayName = newValue
        onRenameSpeaker(speakerID, newValue)
    }

    private func copyTranscriptExport() {
        guard let transcript = meeting.storedTranscript,
              isTranscriptExportAvailable(from: meeting.storedTranscript) else {
            return
        }

        let markdown = renderMeetingTranscriptExportMarkdown(
            meeting: meeting,
            transcript: transcript
        )

        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #endif

        exportFeedbackTask?.cancel()
        exportFeedbackText = "Copied"
        exportFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                exportFeedbackText = nil
                exportFeedbackTask = nil
            }
        }
    }
}
