//
//  CalendarSettingsViewModel.swift
//  QuickMeeting
//
//  Created by Codex on 08.05.2026.
//

import Combine
import Foundation

@MainActor
final class CalendarSettingsViewModel: ObservableObject {
    @Published private(set) var authorizationState: CalendarAuthorizationState
    @Published private(set) var availableCalendars: [CalendarDescriptor] = []
    @Published private(set) var selectedCalendarIDs: [String]

    private let calendarIntegration: any CalendarIntegration
    private let settingsStore: any CalendarSelectionStoring

    init(
        calendarIntegration: any CalendarIntegration,
        settingsStore: any CalendarSelectionStoring
    ) {
        self.calendarIntegration = calendarIntegration
        self.settingsStore = settingsStore
        authorizationState = calendarIntegration.authorizationState()
        selectedCalendarIDs = settingsStore.selectedCalendarIDs()
    }

    var selectedCalendarSummaryText: String {
        "\(selectedCalendarIDs.count) selected"
    }

    func reload() async {
        authorizationState = calendarIntegration.authorizationState()

        guard authorizationState == .authorized else {
            availableCalendars = []
            return
        }

        availableCalendars = calendarIntegration.availableCalendars()

        let storedSelection = settingsStore.selectedCalendarIDs()
        if storedSelection.isEmpty {
            selectedCalendarIDs = availableCalendars.map(\.id)
            settingsStore.saveSelectedCalendarIDs(selectedCalendarIDs)
            return
        }

        let availableIDs = Set(availableCalendars.map(\.id))
        selectedCalendarIDs = storedSelection.filter { availableIDs.contains($0) }
    }

    func requestAccess() async {
        authorizationState = await calendarIntegration.requestAccess()
        await reload()
    }

    func toggleCalendarSelection(id: String) {
        if let index = selectedCalendarIDs.firstIndex(of: id) {
            selectedCalendarIDs.remove(at: index)
        } else {
            selectedCalendarIDs.append(id)
        }

        settingsStore.saveSelectedCalendarIDs(selectedCalendarIDs)
    }

    func selectAllCalendars() {
        selectedCalendarIDs = availableCalendars.map(\.id)
        settingsStore.saveSelectedCalendarIDs(selectedCalendarIDs)
    }

    func selectNoCalendars() {
        selectedCalendarIDs = []
        settingsStore.saveSelectedCalendarIDs(selectedCalendarIDs)
    }
}
