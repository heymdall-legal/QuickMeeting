import Foundation

protocol HuggingFaceTokenSettingsStoring: Sendable {
    func loadToken() -> String
    func saveToken(_ token: String)
}

struct HuggingFaceTokenSettingsStore: HuggingFaceTokenSettingsStoring {
    private let userDefaults: UserDefaults
    private let tokenKey = "transcription.huggingFaceToken"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadToken() -> String {
        userDefaults.string(forKey: tokenKey) ?? ""
    }

    func saveToken(_ token: String) {
        userDefaults.set(token, forKey: tokenKey)
    }
}
