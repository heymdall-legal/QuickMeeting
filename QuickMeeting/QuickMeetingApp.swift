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
    @StateObject private var transcriptionSettingsViewModel: TranscriptionSettingsViewModel
    @StateObject private var meetingSummarySettingsViewModel: MeetingSummarySettingsViewModel
    @State private var menuBarController: MenuBarController?

    init() {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            sharedModelContainer = modelContainer
            let meetingStore = MeetingStore(modelContext: modelContainer.mainContext)
            let knownSpeakerStore = KnownSpeakerStore(modelContext: modelContainer.mainContext)
            let knownSpeakerEnrollmentService = KnownSpeakerEnrollmentService(store: knownSpeakerStore)
            try? meetingStore.resetStuckRecordingMeetings(updatedAt: Date())
            try? meetingStore.resetStuckTranscribingMeetings(updatedAt: Date())
            let meetingFileStore = MeetingFileStore()
            let recordingService = DefaultRecordingService(
                audioCapturePipeline: NativeAudioCapturePipeline()
            )
            let transcriptionProgressCenter = TranscriptionProgressCenter()
            let transcriptionSettingsStore = TranscriptionSettingsStore()
            let transcriptionService = FluidTranscriptionService(
                meetingStore: meetingStore,
                progressCenter: transcriptionProgressCenter,
                knownSpeakerStore: knownSpeakerStore,
                knownSpeakerEnrollmentService: knownSpeakerEnrollmentService,
                languageStore: transcriptionSettingsStore
            )
            let meetingTranscriptStore = MeetingTranscriptStore(meetingStore: meetingStore)
            let calendarSettingsStore = CalendarSettingsStore()
            let calendarIntegration = NativeCalendarIntegration(settingsStore: calendarSettingsStore)
            let autoRecordingSettingsStore = AutoRecordingSettingsStore()
            let meetingSummarySettingsStore = MeetingSummarySettingsStore()
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
                knownSpeakerEnrollmentService: knownSpeakerEnrollmentService,
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
            _transcriptionSettingsViewModel = StateObject(
                wrappedValue: TranscriptionSettingsViewModel(settingsStore: transcriptionSettingsStore)
            )
            _meetingSummarySettingsViewModel = StateObject(
                wrappedValue: MeetingSummarySettingsViewModel(
                    settingsStore: meetingSummarySettingsStore
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

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(
                appViewModel: appViewModel,
                calendarSettingsViewModel: calendarSettingsViewModel,
                autoRecordingSettingsViewModel: autoRecordingSettingsViewModel,
                transcriptionSettingsViewModel: transcriptionSettingsViewModel,
                meetingSummarySettingsViewModel: meetingSummarySettingsViewModel
            )
                .task {
                    if menuBarController == nil {
                        let openWindowAction = openWindow
                        menuBarController = MenuBarController(
                            viewModel: appViewModel,
                            autoRecordingViewModel: autoRecordingSettingsViewModel,
                            modelContainer: sharedModelContainer,
                            onOpenMainWindow: {
                                NSApp.activate(ignoringOtherApps: true)
                                let mainWindow = NSApp.windows.first { window in
                                    guard !(window is NSPanel), window.canBecomeMain else { return false }
                                    let title = window.title.lowercased()
                                    return title != "settings" && title != "preferences"
                                }
                                if let mainWindow {
                                    mainWindow.makeKeyAndOrderFront(nil)
                                } else {
                                    openWindowAction(id: "main")
                                }
                            }
                        )
                    }

                    await autoRecordingSettingsViewModel.load()
                    autoRecordingMonitor.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(sharedModelContainer)
    }
}
