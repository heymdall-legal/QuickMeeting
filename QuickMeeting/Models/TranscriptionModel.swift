//
//  TranscriptionModel.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Foundation

enum TranscriptionModelID: String, CaseIterable, Codable, Sendable {
    case tiny
    case small
    case largeV3
}

struct TranscriptionModel: Identifiable, Equatable, Sendable {
    let id: TranscriptionModelID
    let displayName: String
    let argmaxModelID: String
    let tokenizerRepositoryID: String
    let summary: String
    let sortOrder: Int
}

enum TranscriptionModelInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double?)
    case installed(sizeInBytes: Int64, installedAt: Date?)
    case failed(message: String)
}
