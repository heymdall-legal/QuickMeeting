//
//  ModelSettingsStore.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Foundation

final class ModelSettingsStore {
    private let userDefaults: UserDefaults
    private let defaultModelKey = "defaultTranscriptionModelID"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var defaultModelID: TranscriptionModelID? {
        get {
            guard let rawValue = userDefaults.string(forKey: defaultModelKey) else {
                return nil
            }

            return TranscriptionModelID(rawValue: rawValue)
        }
        set {
            userDefaults.set(newValue?.rawValue, forKey: defaultModelKey)
        }
    }
}
