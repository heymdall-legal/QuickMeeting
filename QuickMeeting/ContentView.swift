//
//  ContentView.swift
//  QuickMeeting
//
//  Created by heymdall on 04.05.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @ObservedObject var appViewModel: AppViewModel
    @ObservedObject var calendarSettingsViewModel: CalendarSettingsViewModel
    @ObservedObject var autoRecordingSettingsViewModel: AutoRecordingSettingsViewModel
    @ObservedObject var transcriptionSettingsViewModel: TranscriptionSettingsViewModel
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @State private var selection = defaultSidebarSelection()
    @State private var isSettingsPresented = false

    var body: some View {
        NavigationSplitView {
            AppSidebarView(
                appViewModel: appViewModel,
                meetings: meetings,
                selection: $selection,
                onOpenSettings: { isSettingsPresented = true }
            )
                .navigationSplitViewColumnWidth(min: 280, ideal: 312)
        } detail: {
            switch selection {
            case .home:
                HomeView(
                    appViewModel: appViewModel,
                    autoRecordingViewModel: autoRecordingSettingsViewModel,
                    meetings: meetings,
                    onSelectMeeting: { id in selection = .meeting(id) },
                    onOpenSettings: { isSettingsPresented = true }
                )
            case .settings:
                SettingsView(
                    calendarViewModel: calendarSettingsViewModel,
                    autoRecordingViewModel: autoRecordingSettingsViewModel
                )
            case .meeting(let meetingID):
                if let selectedMeeting = meetings.first(where: { $0.id == meetingID }) {
                    MeetingDetailView(
                        meeting: selectedMeeting,
                        transcriptionProgress: appViewModel.transcriptionProgress(for: selectedMeeting.id),
                        diarizationProgress: appViewModel.diarizationProgress(for: selectedMeeting.id),
                        canDelete: appViewModel.canDeleteMeeting(selectedMeeting),
                        canTranscribe: appViewModel.canTranscribeMeeting(selectedMeeting),
                        transcriptionDisabledReason: nil,
                        onTranscribe: {
                            Task {
                                await appViewModel.transcribeMeeting(selectedMeeting)
                            }
                        },
                        onDelete: {
                            appViewModel.deleteMeeting(selectedMeeting)
                        },
                        onStop: {
                            Task {
                                await appViewModel.stopRecording()
                            }
                        },
                        onRenameMeeting: { title in
                            try await appViewModel.renameMeeting(selectedMeeting, title: title)
                        },
                        onRenameSpeaker: { speakerID, displayName in
                            Task {
                                try? await appViewModel.renameSpeaker(
                                    meetingID: selectedMeeting.id,
                                    speakerID: speakerID,
                                    displayName: displayName
                                )
                            }
                        }
                    )
                } else {
                    HomeView(
                        appViewModel: appViewModel,
                        autoRecordingViewModel: autoRecordingSettingsViewModel,
                        meetings: meetings,
                        onSelectMeeting: { id in selection = .meeting(id) },
                        onOpenSettings: { isSettingsPresented = true }
                    )
                }
            }
        }
        .onAppear {
            syncSelection()
        }
        .onChange(of: meetings.map(\.id)) { _, _ in
            syncSelection()
        }
        .sheet(isPresented: $isSettingsPresented) {
            QMSettingsSheet(
                calendarViewModel: calendarSettingsViewModel,
                autoRecordingViewModel: autoRecordingSettingsViewModel,
                transcriptionViewModel: transcriptionSettingsViewModel,
                onClose: { isSettingsPresented = false }
            )
        }
        .alert(
            "Unable to Delete Meeting",
            isPresented: deletionErrorIsPresented,
            actions: {
                Button("OK", role: .cancel) {
                    appViewModel.clearDeletionError()
                }
            },
            message: {
                Text(appViewModel.deletionErrorMessage ?? "Unknown error.")
            }
        )
        .alert(
            "Unable to Transcribe Meeting",
            isPresented: transcriptionErrorIsPresented,
            actions: {
                Button("OK", role: .cancel) {
                    appViewModel.clearTranscriptionError()
                }
            },
            message: {
                Text(appViewModel.transcriptionErrorMessage ?? "Unknown error.")
            }
        )
        .alert(
            "Unable to Rename Speaker",
            isPresented: renameSpeakerErrorIsPresented,
            actions: {
                Button("OK", role: .cancel) {
                    appViewModel.clearRenameSpeakerError()
                }
            },
            message: {
                Text(appViewModel.renameSpeakerErrorMessage ?? "Unknown error.")
            }
        )
        .alert(
            "Unable to Rename Meeting",
            isPresented: renameMeetingErrorIsPresented,
            actions: {
                Button("OK", role: .cancel) {
                    appViewModel.clearRenameMeetingError()
                }
            },
            message: {
                Text(appViewModel.renameMeetingErrorMessage ?? "Unknown error.")
            }
        )
    }

    private func syncSelection() {
        selection = reconciledSidebarSelection(
            currentSelection: selection,
            availableMeetingIDs: meetings.map(\.id)
        )
    }

    private var deletionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { appViewModel.deletionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appViewModel.clearDeletionError()
                }
            }
        )
    }

    private var transcriptionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { appViewModel.transcriptionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appViewModel.clearTranscriptionError()
                }
            }
        )
    }

    private var renameSpeakerErrorIsPresented: Binding<Bool> {
        Binding(
            get: { appViewModel.renameSpeakerErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appViewModel.clearRenameSpeakerError()
                }
            }
        )
    }

    private var renameMeetingErrorIsPresented: Binding<Bool> {
        Binding(
            get: { appViewModel.renameMeetingErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appViewModel.clearRenameMeetingError()
                }
            }
        )
    }
}

#Preview {
    let container = previewModelContainer()

    ContentView(
        appViewModel: previewAppViewModel(container: container),
        calendarSettingsViewModel: previewCalendarSettingsViewModel(),
        autoRecordingSettingsViewModel: previewAutoRecordingSettingsViewModel(),
        transcriptionSettingsViewModel: TranscriptionSettingsViewModel(settingsStore: TranscriptionSettingsStore())
    )
        .modelContainer(container)
}

@MainActor
private func previewModelContainer() -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Meeting.self,
        PersistedTranscriptSpeaker.self,
        PersistedTranscriptSegment.self,
        configurations: configuration
    )
    let previewRootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("QuickMeetingPreview", isDirectory: true)
    try? FileManager.default.createDirectory(at: previewRootURL, withIntermediateDirectories: true)
    let sampleMeeting = Meeting(
        title: "Weekly Product Sync",
        startedAt: Date(timeIntervalSince1970: 1_714_561_200),
        endedAt: Date(timeIntervalSince1970: 1_714_564_800),
        status: .completed,
        audioFilePath: previewRootURL.appendingPathComponent("audio.wav").path,
        transcriptPreview: "Weekly product sync transcript",
        transcriptSpeakers: [PersistedTranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1")],
        transcriptSegments: [
            PersistedTranscriptSegment(
                id: UUID(),
                text: "We aligned on the launch checklist, reviewed open bugs, and agreed to ship the beta on Friday.",
                startTime: 0,
                endTime: 60,
                speakerID: "speaker-1"
            )
        ],
        duration: 3_600
    )

    container.mainContext.insert(sampleMeeting)

    return container
}

@MainActor
private func previewAutoRecordingSettingsViewModel() -> AutoRecordingSettingsViewModel {
    AutoRecordingSettingsViewModel(settingsStore: AutoRecordingSettingsStore())
}

@MainActor
private func previewAppViewModel(container: ModelContainer) -> AppViewModel {
    AppViewModel(
        meetingStore: MeetingStore(modelContext: container.mainContext),
        meetingFileStore: MeetingFileStore(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("QuickMeetingPreview", isDirectory: true)
        ),
        recordingService: PreviewRecordingService()
    )
}

@MainActor
private func previewCalendarSettingsViewModel() -> CalendarSettingsViewModel {
    CalendarSettingsViewModel(
        calendarIntegration: NoopCalendarIntegration(),
        settingsStore: CalendarSettingsStore(userDefaults: .standard)
    )
}

@MainActor
private final class PreviewRecordingService: RecordingService {
    func startRecording(meeting _: Meeting, outputURL _: URL) async throws {}

    func stopRecording() async throws {}
}
