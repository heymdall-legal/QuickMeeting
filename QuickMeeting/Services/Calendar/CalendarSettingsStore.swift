//
//  CalendarSettingsStore.swift
//  QuickMeeting
//
//  Created by Codex on 08.05.2026.
//

import Foundation

protocol CalendarSelectionStoring: Sendable {
    func selectedCalendarIDs() -> [String]
    func saveSelectedCalendarIDs(_ ids: [String])
}

struct CalendarSettingsStore: CalendarSelectionStoring {
    private let userDefaults: UserDefaults
    private let selectedCalendarIDsKey = "calendar.selectedIDs"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func selectedCalendarIDs() -> [String] {
        userDefaults.stringArray(forKey: selectedCalendarIDsKey) ?? []
    }

    func saveSelectedCalendarIDs(_ ids: [String]) {
        userDefaults.set(ids, forKey: selectedCalendarIDsKey)
    }
}
