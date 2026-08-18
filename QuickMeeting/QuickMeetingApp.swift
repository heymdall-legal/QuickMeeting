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
    private let onlineDraftCoordinator: OnlineDraftCoordinator
    @StateObject private var appViewModel: AppViewModel
    @StateObject private var calendarSettingsViewModel: CalendarSettingsViewModel
    @StateObject private var autoRecordingSettingsViewModel: AutoRecordingSettingsViewModel
    @StateObject private var transcriptionSettingsViewModel: TranscriptionSettingsViewModel
    @StateObject private var meetingSummarySettingsViewModel: MeetingSummarySettingsViewModel
    @StateObject private var markdownExportSettingsViewModel: MarkdownExportSettingsViewModel
    @State private var menuBarController: MenuBarController?

    init() {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
            PersistedScreenObservation.self,
            PersistedSpeakerIdentitySuggestion.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            sharedModelContainer = modelContainer
            let markdownExportSettingsStore = MeetingMarkdownExportSettingsStore()
            let markdownExporter = ConfiguredMeetingMarkdownExporter(
                settingsStore: markdownExportSettingsStore
            )
            let meetingStore = MeetingStore(
                modelContext: modelContainer.mainContext,
                markdownExporter: markdownExporter
            )
            let screenObservationStore = ScreenObservationStore(modelContext: modelContainer.mainContext)
            let knownSpeakerStore = KnownSpeakerStore(modelContext: modelContainer.mainContext)
            let knownSpeakerEnrollmentService = KnownSpeakerEnrollmentService(store: knownSpeakerStore)
            try? meetingStore.resetStuckRecordingMeetings(updatedAt: Date())
            try? meetingStore.resetStuckTranscribingMeetings(updatedAt: Date())
            let meetingFileStore = MeetingFileStore()
            let onlineAudioChannel = BoundedOnlineAudioChannel()
            let onlineDraftCoordinator = OnlineDraftCoordinator(
                meetingStore: meetingStore,
                channel: onlineAudioChannel,
                pipeline: OnlineDraftPipeline(
                    asrBackend: FluidNemotronStreamingASRBackend(),
                    diarizationBackend: FluidSortformerStreamingDiarizationBackend()
                )
            )
            self.onlineDraftCoordinator = onlineDraftCoordinator
            let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                || NSClassFromString("XCTestCase") != nil
            if !isRunningTests {
                Task { @MainActor in
                    await onlineDraftCoordinator.prepareModels()
                }
            }
            let recordingService = DefaultRecordingService(
                audioCapturePipeline: NativeAudioCapturePipeline(onlineAudioSink: onlineAudioChannel),
                onlineDraftCoordinator: onlineDraftCoordinator
            )
            let transcriptionProgressCenter = TranscriptionProgressCenter()
            let transcriptionSettingsStore = TranscriptionSettingsStore()
            let transcriptionGlossaryStore = TranscriptionGlossaryStore()
            let meetingSummarySettingsStore = MeetingSummarySettingsStore()
            let parakeetBackend = ParakeetASRBackend()
            let asrBackendRouter = ASRBackendRouter(backends: [
                .parakeetTDTv3: parakeetBackend,
                .qwen3ASR17B: NativeQwenASRBackend(),
                .gigaAMV3: NativeGigaAMASRBackend(),
            ])
            let modelPreparationCenter = TranscriptionModelPreparationCenter(
                preparer: asrBackendRouter
            )
            let transcriptionService = FluidTranscriptionService(
                meetingStore: meetingStore,
                progressCenter: transcriptionProgressCenter,
                pipeline: DefaultFluidAudioPipeline(asrBackend: asrBackendRouter),
                knownSpeakerStore: knownSpeakerStore,
                languageStore: transcriptionSettingsStore,
                glossaryStore: transcriptionGlossaryStore,
                correctionService: LLMTranscriptCorrectionService(settingsStore: meetingSummarySettingsStore)
            )
            let meetingTranscriptStore = MeetingTranscriptStore(meetingStore: meetingStore)
            let calendarSettingsStore = CalendarSettingsStore()
            let calendarIntegration = NativeCalendarIntegration(settingsStore: calendarSettingsStore)
            let speakerSuggestionService = DefaultSpeakerSuggestionRecomputeService(
                meetingStore: meetingStore,
                observationStore: screenObservationStore
            )
            let screenSnapshotRecorder = NativeScreenSnapshotRecorder(
                meetingFileStore: meetingFileStore,
                attendeeNamesProvider: { meetingID in
                    await MainActor.run {
                        (try? meetingStore.fetchMeeting(id: meetingID).attendeeNames) ?? []
                    }
                }
            )
            let screenObservationCaptureService = MeetingScreenObservationCaptureService(
                recorder: screenSnapshotRecorder,
                observationSink: ScreenObservationStoreSink(store: screenObservationStore)
            )
            let screenObservationCaptureController = MeetingScreenObservationCaptureController(
                service: screenObservationCaptureService
            )
            let autoRecordingSettingsStore = AutoRecordingSettingsStore()
            let meetingSummaryService = MeetingSummaryService(
                meetingStore: meetingStore,
                settingsStore: meetingSummarySettingsStore
            )
            let autoRecordingSettingsViewModel = AutoRecordingSettingsViewModel(
                settingsStore: autoRecordingSettingsStore
            )
            let appViewModel = AppViewModel(
                meetingStore: meetingStore,
                meetingFileStore: meetingFileStore,
                recordingService: recordingService,
                transcriptionService: transcriptionService,
                meetingSummaryService: meetingSummaryService,
                meetingSummarySettingsStore: meetingSummarySettingsStore,
                transcriptionProgressCenter: transcriptionProgressCenter,
                meetingTranscriptStore: meetingTranscriptStore,
                knownSpeakerEnrollmentService: knownSpeakerEnrollmentService,
                calendarIntegration: calendarIntegration,
                speakerSuggestionService: speakerSuggestionService,
                screenObservationCapturer: screenObservationCaptureController
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
                wrappedValue: TranscriptionSettingsViewModel(
                    settingsStore: transcriptionSettingsStore,
                    glossaryStore: transcriptionGlossaryStore,
                    modelPreparationCenter: modelPreparationCenter,
                    onlineDraftCoordinator: onlineDraftCoordinator
                )
            )
            _meetingSummarySettingsViewModel = StateObject(
                wrappedValue: MeetingSummarySettingsViewModel(
                    settingsStore: meetingSummarySettingsStore
                )
            )
            _markdownExportSettingsViewModel = StateObject(
                wrappedValue: MarkdownExportSettingsViewModel(
                    settingsStore: markdownExportSettingsStore,
                    meetingStore: meetingStore
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
                meetingSummarySettingsViewModel: meetingSummarySettingsViewModel,
                markdownExportSettingsViewModel: markdownExportSettingsViewModel
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
