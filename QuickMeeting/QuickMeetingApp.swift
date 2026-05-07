//
//  QuickMeetingApp.swift
//  QuickMeeting
//
//  Created by heymdall on 04.05.2026.
//

import SwiftUI
import SwiftData

@main
struct QuickMeetingApp: App {
    private let sharedModelContainer: ModelContainer
    @StateObject private var appViewModel: AppViewModel
    @StateObject private var modelsSettingsViewModel: ModelsSettingsViewModel
    @State private var menuBarController: MenuBarController?

    init() {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            sharedModelContainer = modelContainer
            let meetingStore = MeetingStore(modelContext: modelContainer.mainContext)
            let meetingFileStore = MeetingFileStore()
            let recordingService = DefaultRecordingService(
                audioCapturePipeline: NativeAudioCapturePipeline()
            )
            let modelSettingsStore = ModelSettingsStore()
            let modelStore = ArgmaxWhisperModelStore()
            let transcriptionProgressCenter = TranscriptionProgressCenter()
            let transcriptionService = TranscriptionService(
                meetingStore: meetingStore,
                modelStore: modelStore,
                modelSettingsStore: modelSettingsStore,
                backend: WhisperKitTranscriptionBackend(),
                diarizer: DefaultTranscriptDiarizer(),
                progressCenter: transcriptionProgressCenter
            )
            let transcriptionModelManager = TranscriptionModelManager(
                modelStore: modelStore,
                settingsStore: modelSettingsStore
            )
            let meetingTranscriptStore = MeetingTranscriptStore(meetingStore: meetingStore)
            _appViewModel = StateObject(
                wrappedValue: AppViewModel(
                    meetingStore: meetingStore,
                    meetingFileStore: meetingFileStore,
                    recordingService: recordingService,
                    transcriptionService: transcriptionService,
                    transcriptionProgressCenter: transcriptionProgressCenter,
                    meetingTranscriptStore: meetingTranscriptStore
                )
            )
            _modelsSettingsViewModel = StateObject(
                wrappedValue: ModelsSettingsViewModel(manager: transcriptionModelManager)
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                appViewModel: appViewModel,
                modelsViewModel: modelsSettingsViewModel
            )
                .task {
                    if menuBarController == nil {
                        menuBarController = MenuBarController(viewModel: appViewModel)
                    }
                }
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView(modelsViewModel: modelsSettingsViewModel)
        }
    }
}
