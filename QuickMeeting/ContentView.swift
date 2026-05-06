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
    @ObservedObject var modelsViewModel: ModelsSettingsViewModel
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @State private var selection = defaultSidebarSelection()

    var body: some View {
        NavigationSplitView {
            AppSidebarView(meetings: meetings, selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            switch selection {
            case .home:
                HomeView(appViewModel: appViewModel)
            case .settings:
                ModelsSettingsView(viewModel: modelsViewModel)
            case .meeting(let meetingID):
                if let selectedMeeting = meetings.first(where: { $0.id == meetingID }) {
                    MeetingDetailView(
                        meeting: selectedMeeting,
                        canDelete: appViewModel.canDeleteMeeting(selectedMeeting),
                        canTranscribe: appViewModel.canTranscribeMeeting(selectedMeeting),
                        onTranscribe: {
                            Task {
                                await appViewModel.transcribeMeeting(selectedMeeting)
                            }
                        },
                        onDelete: {
                            appViewModel.deleteMeeting(selectedMeeting)
                        }
                    )
                } else {
                    HomeView(appViewModel: appViewModel)
                }
            }
        }
        .onAppear {
            syncSelection()
        }
        .onChange(of: meetings.map(\.id)) { _, _ in
            syncSelection()
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
}

#Preview {
    let container = previewModelContainer()

    ContentView(
        appViewModel: previewAppViewModel(container: container),
        modelsViewModel: previewModelsSettingsViewModel()
    )
        .modelContainer(container)
}

@MainActor
private func previewModelContainer() -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Meeting.self, configurations: configuration)
    let sampleMeeting = Meeting(
        title: "Weekly Product Sync",
        startedAt: Date(timeIntervalSince1970: 1_714_561_200),
        endedAt: Date(timeIntervalSince1970: 1_714_564_800),
        status: .recorded,
        audioFilePath: "/Users/preview/Library/Application Support/QuickMeeting/Meetings/sample/audio.wav",
        duration: 3_600
    )

    container.mainContext.insert(sampleMeeting)

    return container
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
private func previewModelsSettingsViewModel() -> ModelsSettingsViewModel {
    ModelsSettingsViewModel(
        manager: TranscriptionModelManager(
            modelStore: ArgmaxWhisperModelStore(),
            settingsStore: ModelSettingsStore()
        )
    )
}

@MainActor
private final class PreviewRecordingService: RecordingService {
    func startRecording(meeting _: Meeting, outputURL _: URL) async throws {}

    func stopRecording() async throws {}
}
