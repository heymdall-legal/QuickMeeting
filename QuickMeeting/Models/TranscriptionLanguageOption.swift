//
//  TranscriptionLanguageOption.swift
//  QuickMeeting
//
//  Languages offered for the default transcription language setting. `code`
//  is `nil` for auto-detect; otherwise it is a FluidAudio `Language` raw value
//  (an ISO 639-1 code) passed to the ASR pipeline as a script hint.
//

import Foundation

struct TranscriptionLanguageOption: Identifiable, Equatable, Sendable {
    /// `nil` means auto-detect (no language hint passed to the model).
    let code: String?
    let name: String

    var id: String { code ?? "auto" }

    static let all: [TranscriptionLanguageOption] = [
        TranscriptionLanguageOption(code: nil, name: "Auto-detect"),
        TranscriptionLanguageOption(code: "en", name: "English"),
        TranscriptionLanguageOption(code: "es", name: "Spanish"),
        TranscriptionLanguageOption(code: "fr", name: "French"),
        TranscriptionLanguageOption(code: "de", name: "German"),
        TranscriptionLanguageOption(code: "it", name: "Italian"),
        TranscriptionLanguageOption(code: "pt", name: "Portuguese"),
        TranscriptionLanguageOption(code: "nl", name: "Dutch"),
        TranscriptionLanguageOption(code: "pl", name: "Polish"),
        TranscriptionLanguageOption(code: "ru", name: "Russian"),
        TranscriptionLanguageOption(code: "uk", name: "Ukrainian"),
    ]

    static func name(for code: String?) -> String {
        all.first { $0.code == code }?.name ?? "Auto-detect"
    }
}
