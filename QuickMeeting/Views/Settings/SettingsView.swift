//
//  SettingsView.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import SwiftUI

struct SettingsView: View {
    @State private var selection: SettingsPane? = .models
    @ObservedObject var modelsViewModel: ModelsSettingsViewModel

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .navigationTitle("Settings")
        } detail: {
            switch selection ?? .models {
            case .models:
                ModelsSettingsView(viewModel: modelsViewModel)
            }
        }
        .frame(minWidth: 760, minHeight: 460)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case models

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models:
            return "Models"
        }
    }

    var systemImage: String {
        switch self {
        case .models:
            return "waveform.badge.magnifyingglass"
        }
    }
}
