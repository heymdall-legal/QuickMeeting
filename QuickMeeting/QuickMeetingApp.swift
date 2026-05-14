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
    private let autoRecordingMonitor: MeetingAppMonitor
    @StateObject private var appViewModel: AppViewModel
    @StateObject private var modelsSettingsViewModel: ModelsSettingsViewModel
    @StateObject private var calendarSettingsViewModel: CalendarSettingsViewModel
    @StateObject private var autoRecordingSettingsViewModel: AutoRecordingSettingsViewModel
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
            let calendarSettingsStore = CalendarSettingsStore()
            let calendarIntegration = NativeCalendarIntegration(settingsStore: calendarSettingsStore)
            let autoRecordingSettingsStore = AutoRecordingSettingsStore()
            let autoRecordingSettingsViewModel = AutoRecordingSettingsViewModel(
                settingsStore: autoRecordingSettingsStore
            )
            let appViewModel = AppViewModel(
                meetingStore: meetingStore,
                meetingFileStore: meetingFileStore,
                recordingService: recordingService,
                transcriptionService: transcriptionService,
                transcriptionProgressCenter: transcriptionProgressCenter,
                meetingTranscriptStore: meetingTranscriptStore,
                calendarIntegration: calendarIntegration
            )
            let autoRecordingSettings = autoRecordingSettingsStore.load()
            let autoRecordingCoordinator = AutoRecordingCoordinator(
                clock: TaskSleepAutoRecordingClock(),
                intentSink: appViewModel,
                startDelay: autoRecordingSettings.startDelay,
                stopGracePeriod: autoRecordingSettings.stopGracePeriod
            )
            appViewModel.attachAutoRecordingCoordinator(autoRecordingCoordinator)
            _appViewModel = StateObject(wrappedValue: appViewModel)
            _modelsSettingsViewModel = StateObject(
                wrappedValue: ModelsSettingsViewModel(manager: transcriptionModelManager)
            )
            _calendarSettingsViewModel = StateObject(
                wrappedValue: CalendarSettingsViewModel(
                    calendarIntegration: calendarIntegration,
                    settingsStore: calendarSettingsStore
                )
            )
            _autoRecordingSettingsViewModel = StateObject(
                wrappedValue: autoRecordingSettingsViewModel
            )
            autoRecordingMonitor = MeetingAppMonitor(
                settingsStore: autoRecordingSettingsStore,
                activitySource: NativeMeetingAppActivitySource(),
                presenceSink: appViewModel
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                appViewModel: appViewModel,
                modelsViewModel: modelsSettingsViewModel,
                calendarSettingsViewModel: calendarSettingsViewModel,
                autoRecordingSettingsViewModel: autoRecordingSettingsViewModel
            )
                .task {
                    if menuBarController == nil {
                        menuBarController = MenuBarController(viewModel: appViewModel)
                    }

                    autoRecordingMonitor.start()
                }
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView(
                modelsViewModel: modelsSettingsViewModel,
                calendarViewModel: calendarSettingsViewModel,
                autoRecordingViewModel: autoRecordingSettingsViewModel
            )
        }
    }
}
