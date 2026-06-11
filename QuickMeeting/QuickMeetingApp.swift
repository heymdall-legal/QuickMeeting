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
    @StateObject private var calendarSettingsViewModel: CalendarSettingsViewModel
    @StateObject private var autoRecordingSettingsViewModel: AutoRecordingSettingsViewModel
    @StateObject private var huggingFaceTokenSettingsViewModel: HuggingFaceTokenSettingsViewModel
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
            try? meetingStore.resetStuckTranscribingMeetings(updatedAt: Date())
            let meetingFileStore = MeetingFileStore()
            let recordingService = DefaultRecordingService(
                audioCapturePipeline: NativeAudioCapturePipeline()
            )
            let transcriptionProgressCenter = TranscriptionProgressCenter()
            let huggingFaceTokenSettingsStore = HuggingFaceTokenSettingsStore()
            let transcriptionService = SidecarTranscriptionService(
                meetingStore: meetingStore,
                progressCenter: transcriptionProgressCenter,
                launcher: DefaultSidecarProcessLauncher(),
                executableURLProvider: {
                    SidecarTranscriptionService.defaultExecutableURL()
                },
                hfTokenProvider: {
                    huggingFaceTokenSettingsStore.loadToken()
                },
                hfHomeURLProvider: {
                    SidecarTranscriptionService.defaultHFHomeURL()
                }
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
            _calendarSettingsViewModel = StateObject(
                wrappedValue: CalendarSettingsViewModel(
                    calendarIntegration: calendarIntegration,
                    settingsStore: calendarSettingsStore
                )
            )
            _autoRecordingSettingsViewModel = StateObject(
                wrappedValue: autoRecordingSettingsViewModel
            )
            _huggingFaceTokenSettingsViewModel = StateObject(
                wrappedValue: HuggingFaceTokenSettingsViewModel(
                    settingsStore: huggingFaceTokenSettingsStore
                )
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
                calendarSettingsViewModel: calendarSettingsViewModel,
                autoRecordingSettingsViewModel: autoRecordingSettingsViewModel,
                huggingFaceTokenSettingsViewModel: huggingFaceTokenSettingsViewModel
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
                calendarViewModel: calendarSettingsViewModel,
                autoRecordingViewModel: autoRecordingSettingsViewModel,
                huggingFaceTokenViewModel: huggingFaceTokenSettingsViewModel
            )
        }
    }
}
