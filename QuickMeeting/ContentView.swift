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
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @State private var selectedMeetingID: UUID?

    var body: some View {
        NavigationSplitView {
            MeetingListView(meetings: meetings, selection: selectionBinding)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                .navigationTitle("Meetings")
        } detail: {
            if let selectedMeeting {
                MeetingDetailView(meeting: selectedMeeting)
            } else {
                ContentUnavailableView(
                    "Select a Meeting",
                    systemImage: "rectangle.stack",
                    description: Text("Choose a meeting from the library to review its recording details.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup {
                RecordingToolbarControls(appViewModel: appViewModel)
            }
        }
        .onAppear {
            syncSelection()
        }
        .onChange(of: meetings.map(\.id)) { _, _ in
            syncSelection()
        }
        .onChange(of: appViewModel.activeOrRecoverableMeetingID) { _, _ in
            syncSelection()
        }
    }

    private var selectedMeeting: Meeting? {
        guard let selectedMeetingID = effectiveSelectedMeetingID else {
            return nil
        }

        return meetings.first { $0.id == selectedMeetingID }
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { effectiveSelectedMeetingID },
            set: { newValue in
                if let pinnedMeetingID = appViewModel.activeOrRecoverableMeetingID {
                    selectedMeetingID = pinnedMeetingID
                    return
                }

                selectedMeetingID = newValue
            }
        )
    }

    private var effectiveSelectedMeetingID: UUID? {
        appViewModel.activeOrRecoverableMeetingID ?? selectedMeetingID
    }

    private func syncSelection() {
        if let pinnedMeetingID = appViewModel.activeOrRecoverableMeetingID,
           meetings.contains(where: { $0.id == pinnedMeetingID }) {
            selectedMeetingID = pinnedMeetingID
            return
        }

        guard let firstMeeting = meetings.first else {
            selectedMeetingID = nil
            return
        }

        guard let selectedMeetingID else {
            self.selectedMeetingID = firstMeeting.id
            return
        }

        if meetings.contains(where: { $0.id == selectedMeetingID }) {
            return
        }

        self.selectedMeetingID = firstMeeting.id
    }
}

#Preview {
    let container = previewModelContainer()

    ContentView(appViewModel: previewAppViewModel(container: container))
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
private final class PreviewRecordingService: RecordingService {
    func startRecording(meeting _: Meeting, outputURL _: URL) async throws {}

    func stopRecording() async throws {}
}
