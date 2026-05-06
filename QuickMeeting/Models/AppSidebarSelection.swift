//
//  AppSidebarSelection.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation

enum AppSidebarSelection: Hashable {
    case home
    case settings
    case meeting(UUID)
}
