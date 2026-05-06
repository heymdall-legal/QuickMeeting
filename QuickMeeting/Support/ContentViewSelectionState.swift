//
//  ContentViewSelectionState.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation

func defaultSidebarSelection() -> AppSidebarSelection {
    .home
}

func reconciledSidebarSelection(
    currentSelection: AppSidebarSelection,
    availableMeetingIDs: [UUID]
) -> AppSidebarSelection {
    switch currentSelection {
    case .meeting(let meetingID):
        if availableMeetingIDs.contains(meetingID) {
            return .meeting(meetingID)
        }

        return .home
    case .home, .settings:
        return currentSelection
    }
}
