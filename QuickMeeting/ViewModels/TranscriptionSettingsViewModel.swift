//
//  TranscriptionSettingsViewModel.swift
//  QuickMeeting
//
//  Backs the default-language control in the Settings sheet.
//

import Combine
import Foundation

@MainActor
final class TranscriptionSettingsViewModel: ObservableObject {
    @Published private(set) var languageCode: String?

    private let settingsStore: any TranscriptionLanguageStoring

    init(settingsStore: any TranscriptionLanguageStoring) {
        self.settingsStore = settingsStore
        languageCode = settingsStore.languageCode()
    }

    var options: [TranscriptionLanguageOption] { TranscriptionLanguageOption.all }

    var selectedLanguageName: String { TranscriptionLanguageOption.name(for: languageCode) }

    func selectLanguage(code: String?) {
        languageCode = code
        settingsStore.saveLanguageCode(code)
    }
}
