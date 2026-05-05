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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            sharedModelContainer = modelContainer
            let transcriptionModelManager = TranscriptionModelManager(
                modelStore: ArgmaxWhisperModelStore(),
                settingsStore: ModelSettingsStore()
            )
            _appViewModel = StateObject(
                wrappedValue: AppViewModel(
                    meetingStore: MeetingStore(modelContext: modelContainer.mainContext),
                    meetingFileStore: MeetingFileStore(),
                    recordingService: DefaultRecordingService(
                        audioCapturePipeline: NativeAudioCapturePipeline()
                    )
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
            ContentView(appViewModel: appViewModel)
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
