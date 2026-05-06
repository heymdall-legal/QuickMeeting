//
//  Meeting.swift
//  QuickMeeting
//
//  Created by heymdall on 04.05.2026.
//

import Foundation
import SwiftData

enum MeetingError: Error, Equatable {
    case invalidStatusRawValue(String)
}

@Model
final class Meeting {
    @Attribute(.unique) private(set) var id: UUID
    private(set) var title: String
    private(set) var startedAt: Date
    private(set) var endedAt: Date?
    private var statusRawValue: String
    private(set) var audioFilePath: String
    private(set) var transcriptFilePath: String?
    private(set) var transcriptPreview: String?
    private(set) var duration: TimeInterval?
    private(set) var calendarEventID: String?
    private(set) var createdAt: Date
    private(set) var updatedAt: Date

    var status: MeetingStatus {
        get throws {
            guard let status = MeetingStatus(rawValue: statusRawValue) else {
                throw MeetingError.invalidStatusRawValue(statusRawValue)
            }

            return status
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        status: MeetingStatus,
        audioFilePath: String,
        transcriptFilePath: String? = nil,
        transcriptPreview: String? = nil,
        duration: TimeInterval? = nil,
        calendarEventID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.statusRawValue = status.rawValue
        self.audioFilePath = audioFilePath
        self.transcriptFilePath = transcriptFilePath
        self.transcriptPreview = transcriptPreview
        self.duration = duration
        self.calendarEventID = calendarEventID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func setStatus(_ newStatus: MeetingStatus, updatedAt: Date = Date()) {
        statusRawValue = newStatus.rawValue
        touch(updatedAt: updatedAt)
    }

    func finishRecording(endedAt: Date, duration: TimeInterval, updatedAt: Date = Date()) {
        self.endedAt = endedAt
        self.duration = duration
        statusRawValue = MeetingStatus.recorded.rawValue
        touch(updatedAt: updatedAt)
    }

    func beginTranscription(updatedAt: Date = Date()) {
        statusRawValue = MeetingStatus.transcribing.rawValue
        touch(updatedAt: updatedAt)
    }

    func completeTranscription(
        transcriptFilePath: String,
        transcriptPreview: String,
        updatedAt: Date = Date()
    ) {
        self.transcriptFilePath = transcriptFilePath
        self.transcriptPreview = transcriptPreview
        statusRawValue = MeetingStatus.completed.rawValue
        touch(updatedAt: updatedAt)
    }

    func failTranscription(updatedAt: Date = Date()) {
        statusRawValue = MeetingStatus.failed.rawValue
        touch(updatedAt: updatedAt)
    }

    private func touch(updatedAt: Date) {
        self.updatedAt = updatedAt
    }
}
