//
//  MeetingStore.swift
//  QuickMeeting
//
//  Created by heymdall on 04.05.2026.
//

import Foundation
import SwiftData

enum MeetingStoreError: LocalizedError, Equatable {
    case audioFileOutsideRecordingFolder
    case meetingNotFound
    case invalidMeetingTitle

    var errorDescription: String? {
        switch self {
        case .audioFileOutsideRecordingFolder:
            return "Recording files must stay inside the meeting folder."
        case .meetingNotFound:
            return "Meeting could not be found."
        case .invalidMeetingTitle:
            return "Meeting title cannot be empty."
        }
    }
}

struct MeetingStore {
    let modelContext: ModelContext
    let markdownExporter: (any MeetingMarkdownExporting)?

    init(
        modelContext: ModelContext,
        markdownExporter: (any MeetingMarkdownExporting)? = nil
    ) {
        self.modelContext = modelContext
        self.markdownExporter = markdownExporter
    }

    @discardableResult
    func createMeeting(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        attendeeNames: [String] = [],
        calendarEventID: String? = nil,
        folderURL: URL,
        audioFileURL: URL
    ) throws -> Meeting {
        let now = Date()
        let recordingFolderURL = folderURL.standardizedFileURL
        let normalizedAudioFileURL = audioFileURL.standardizedFileURL

        guard MeetingStore.isFileURL(normalizedAudioFileURL, inside: recordingFolderURL) else {
            throw MeetingStoreError.audioFileOutsideRecordingFolder
        }

        let meeting = Meeting(
            id: id,
            title: title,
            startedAt: startedAt,
            status: .recording,
            audioFilePath: normalizedAudioFileURL.path(percentEncoded: false),
            calendarEventID: calendarEventID,
            attendeeNames: attendeeNames,
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(meeting)
        try modelContext.save()

        return meeting
    }

    private static func isFileURL(_ fileURL: URL, inside directoryURL: URL) -> Bool {
        let directoryComponents = directoryURL.pathComponents
        let fileComponents = fileURL.pathComponents

        guard fileComponents.count > directoryComponents.count else {
            return false
        }

        return Array(fileComponents.prefix(directoryComponents.count)) == directoryComponents
    }

    func deleteMeeting(_ meeting: Meeting) throws {
        try? markdownExporter?.removeTranscript(for: meeting.id)
        try? markdownExporter?.removeSummary(for: meeting.id)
        modelContext.delete(meeting)
        try modelContext.save()
    }

    func fetchMeetings() throws -> [Meeting] {
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchMeeting(id: UUID) throws -> Meeting {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { meeting in
                meeting.id == id
            }
        )

        guard let meeting = try modelContext.fetch(descriptor).first else {
            throw MeetingStoreError.meetingNotFound
        }

        return meeting
    }

    func finishRecording(meetingID: UUID, endedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.finishRecording(
            endedAt: endedAt,
            duration: endedAt.timeIntervalSince(meeting.startedAt),
            updatedAt: endedAt
        )
        try modelContext.save()
    }

    func renameMeeting(meetingID: UUID, title: String, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTitle.isEmpty else {
            throw MeetingStoreError.invalidMeetingTitle
        }

        meeting.renameTitle(to: normalizedTitle, updatedAt: updatedAt)
        try modelContext.save()
        syncMarkdownExportBestEffort(for: meeting)
    }

    func updateCalendarEvent(
        meetingID: UUID,
        eventTitle: String,
        attendeeNames: [String],
        calendarEventID: String?,
        updatedAt: Date
    ) throws {
        let meeting = try fetchMeeting(id: meetingID)
        let normalizedTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTitle.isEmpty else {
            throw MeetingStoreError.invalidMeetingTitle
        }

        let normalizedAttendeeNames = attendeeNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        meeting.updateCalendarEvent(
            title: normalizedTitle,
            attendeeNames: normalizedAttendeeNames,
            calendarEventID: calendarEventID,
            updatedAt: updatedAt
        )
        try modelContext.save()
        syncMarkdownExportBestEffort(for: meeting)
    }

    func startTranscription(meetingID: UUID, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.beginTranscription(updatedAt: updatedAt)
        try modelContext.save()
        syncMarkdownExportBestEffort(for: meeting)
    }

    func completeTranscription(
        meetingID: UUID,
        transcript: StoredTranscript,
        transcriptPreview: String,
        rawTranscript: StoredTranscript? = nil,
        correctedTranscript: StoredTranscript? = nil,
        pipelineMetadata: TranscriptionPipelineMetadata? = nil,
        updatedAt: Date
    ) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.completeTranscription(
            transcript: transcript,
            transcriptPreview: transcriptPreview,
            rawTranscript: rawTranscript,
            correctedTranscript: correctedTranscript,
            pipelineMetadata: pipelineMetadata,
            updatedAt: updatedAt
        )
        try modelContext.save()
        syncMarkdownExportBestEffort(for: meeting)
    }

    func saveSummary(meetingID: UUID, summary: String, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.storeSummary(summary, updatedAt: updatedAt)
        try modelContext.save()
        syncMarkdownExportBestEffort(for: meeting)
    }

    func storeRealtimeTranscript(meetingID: UUID, text: String, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.storeRealtimeTranscript(text, updatedAt: updatedAt)
        try modelContext.save()
    }

    @discardableResult
    func renameSpeaker(
        meetingID: UUID,
        speakerID: String,
        displayName: String,
        updatedAt: Date
    ) throws -> StoredTranscript {
        let meeting = try fetchMeeting(id: meetingID)
        guard meeting.storedTranscript != nil else {
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        guard let speaker = meeting.transcriptSpeakers.first(where: { $0.id == speakerID }) else {
            throw MeetingTranscriptStoreError.speakerNotFound
        }

        speaker.displayName = displayName
        speaker.labelSourceRawValue = TranscriptSpeakerLabelSource.userAssigned.rawValue
        if speaker.matchedKnownSpeakerID != nil {
            speaker.matchedKnownSpeakerID = nil
        }
        meeting.setStatus(try meeting.status, updatedAt: updatedAt)
        try modelContext.save()

        guard let transcript = meeting.storedTranscript else {
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        syncMarkdownExportBestEffort(for: meeting)
        return transcript
    }

    @discardableResult
    func updateTranscriptSegmentText(
        meetingID: UUID,
        segmentID: UUID,
        text: String,
        updatedAt: Date
    ) throws -> StoredTranscript {
        let meeting = try fetchMeeting(id: meetingID)
        let transcript = try requireStoredTranscript(from: meeting)
        let normalizedText = try normalizedTranscriptSegmentText(text)
        guard let segmentIndex = transcript.segments.firstIndex(where: { $0.id == segmentID }) else {
            throw MeetingTranscriptStoreError.segmentNotFound
        }

        var segments = transcript.segments
        let segment = segments[segmentIndex]
        segments[segmentIndex] = TranscriptSegment(
            id: segment.id,
            text: normalizedText,
            startTime: segment.startTime,
            endTime: segment.endTime,
            speakerID: segment.speakerID
        )

        return try replaceTranscript(
            meeting,
            speakers: transcript.speakers,
            segments: segments,
            updatedAt: updatedAt
        )
    }

    @discardableResult
    func splitTranscriptSegment(
        meetingID: UUID,
        segmentID: UUID,
        cursorOffset: Int,
        updatedAt: Date
    ) throws -> TranscriptSegment {
        let meeting = try fetchMeeting(id: meetingID)
        let transcript = try requireStoredTranscript(from: meeting)
        guard let segmentIndex = transcript.segments.firstIndex(where: { $0.id == segmentID }) else {
            throw MeetingTranscriptStoreError.segmentNotFound
        }

        let segment = transcript.segments[segmentIndex]
        let split = try splitTranscriptSegmentText(segment.text, cursorOffset: cursorOffset)
        let updatedOriginal = TranscriptSegment(
            id: segment.id,
            text: split.left,
            startTime: segment.startTime,
            endTime: nil,
            speakerID: segment.speakerID
        )
        let newSegment = TranscriptSegment(
            text: split.right,
            startTime: nil,
            endTime: segment.endTime,
            speakerID: segment.speakerID
        )

        var segments = transcript.segments
        segments[segmentIndex] = updatedOriginal
        segments.insert(newSegment, at: segmentIndex + 1)
        _ = try replaceTranscript(
            meeting,
            speakers: transcript.speakers,
            segments: segments,
            updatedAt: updatedAt
        )

        return newSegment
    }

    @discardableResult
    func mergeTranscriptSegmentWithPrevious(
        meetingID: UUID,
        segmentID: UUID,
        updatedAt: Date
    ) throws -> TranscriptSegment {
        let meeting = try fetchMeeting(id: meetingID)
        let transcript = try requireStoredTranscript(from: meeting)
        guard let segmentIndex = transcript.segments.firstIndex(where: { $0.id == segmentID }) else {
            throw MeetingTranscriptStoreError.segmentNotFound
        }
        guard segmentIndex > transcript.segments.startIndex else {
            throw MeetingTranscriptStoreError.previousSegmentNotFound
        }

        let previousIndex = transcript.segments.index(before: segmentIndex)
        let previous = transcript.segments[previousIndex]
        let current = transcript.segments[segmentIndex]
        let merged = TranscriptSegment(
            id: previous.id,
            text: mergedTranscriptSegmentText(previous: previous.text, current: current.text),
            startTime: previous.startTime,
            endTime: current.endTime ?? previous.endTime,
            speakerID: previous.speakerID
        )

        var segments = transcript.segments
        segments[previousIndex] = merged
        segments.remove(at: segmentIndex)
        _ = try replaceTranscript(
            meeting,
            speakers: transcript.speakers,
            segments: segments,
            updatedAt: updatedAt
        )

        return merged
    }

    @discardableResult
    func assignTranscriptSegment(
        meetingID: UUID,
        segmentID: UUID,
        displayName: String,
        updatedAt: Date
    ) throws -> StoredTranscript {
        let meeting = try fetchMeeting(id: meetingID)
        let transcript = try requireStoredTranscript(from: meeting)
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw MeetingTranscriptStoreError.invalidSpeakerName
        }
        guard let segmentIndex = transcript.segments.firstIndex(where: { $0.id == segmentID }) else {
            throw MeetingTranscriptStoreError.segmentNotFound
        }

        var speakers = transcript.speakers
        let speakerID: String
        if let existingSpeaker = speakers.first(where: { $0.displayName.compare(normalizedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            speakerID = existingSpeaker.id
        } else {
            speakerID = nextTranscriptSpeakerID(existing: speakers)
            speakers.append(
                TranscriptSpeaker(
                    id: speakerID,
                    displayName: normalizedName,
                    labelSource: .userAssigned
                )
            )
        }

        var segments = transcript.segments
        let segment = segments[segmentIndex]
        segments[segmentIndex] = TranscriptSegment(
            id: segment.id,
            text: segment.text,
            startTime: segment.startTime,
            endTime: segment.endTime,
            speakerID: speakerID
        )

        return try replaceTranscript(
            meeting,
            speakers: speakers,
            segments: segments,
            updatedAt: updatedAt
        )
    }

    func exportMarkdownForExistingMeetings() throws {
        guard let markdownExporter else {
            return
        }

        for meeting in try fetchMeetings() {
            try syncMarkdownExport(for: meeting, using: markdownExporter)
        }
    }

    func failTranscription(meetingID: UUID, updatedAt: Date) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.failTranscription(updatedAt: updatedAt)
        try modelContext.save()
    }

    func storeWaveform(meetingID: UUID, samples: [Double]) throws {
        let meeting = try fetchMeeting(id: meetingID)
        meeting.storeWaveform(samples, updatedAt: Date())
        try modelContext.save()
    }

    func resetStuckTranscribingMeetings(updatedAt: Date) throws {
        let allMeetings = try modelContext.fetch(FetchDescriptor<Meeting>())
        var didChange = false
        for meeting in allMeetings where (try? meeting.status) == .transcribing {
            meeting.failTranscription(updatedAt: updatedAt)
            didChange = true
        }
        if didChange {
            try modelContext.save()
        }
    }

    func resetStuckRecordingMeetings(updatedAt: Date) throws {
        let allMeetings = try modelContext.fetch(FetchDescriptor<Meeting>())
        var didChange = false
        for meeting in allMeetings where (try? meeting.status) == .recording {
            if hasRecoverableAudioFile(for: meeting) {
                meeting.finishRecording(
                    endedAt: updatedAt,
                    duration: updatedAt.timeIntervalSince(meeting.startedAt),
                    updatedAt: updatedAt
                )
            } else {
                meeting.setStatus(.failed, updatedAt: updatedAt)
            }
            didChange = true
        }
        if didChange {
            try modelContext.save()
        }
    }

    private func hasRecoverableAudioFile(for meeting: Meeting) -> Bool {
        let fileURL = URL(fileURLWithPath: meeting.audioFilePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attributes?[.size] as? NSNumber else {
            return false
        }

        return fileSize.uint64Value > 0
    }

    private func requireStoredTranscript(from meeting: Meeting) throws -> StoredTranscript {
        guard let transcript = meeting.storedTranscript else {
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        return transcript
    }

    private func replaceTranscript(
        _ meeting: Meeting,
        speakers: [TranscriptSpeaker],
        segments: [TranscriptSegment],
        updatedAt: Date
    ) throws -> StoredTranscript {
        meeting.replaceTranscript(speakers: speakers, segments: segments, updatedAt: updatedAt)
        try modelContext.save()
        syncMarkdownExportBestEffort(for: meeting)

        guard let transcript = meeting.storedTranscript else {
            throw MeetingTranscriptStoreError.transcriptMissing
        }

        return transcript
    }

    private func normalizedTranscriptSegmentText(_ text: String) throws -> String {
        let normalizedText = text.trimmingCharacters(in: .newlines)
        guard !normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeetingTranscriptStoreError.invalidSegmentText
        }

        return normalizedText
    }

    private func splitTranscriptSegmentText(
        _ text: String,
        cursorOffset: Int
    ) throws -> (left: String, right: String) {
        guard cursorOffset > 0, cursorOffset < text.utf16.count else {
            throw MeetingTranscriptStoreError.invalidSplitLocation
        }

        let splitIndex = String.Index(utf16Offset: cursorOffset, in: text)
        let left = String(text[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = String(text[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else {
            throw MeetingTranscriptStoreError.invalidSplitLocation
        }

        return (left, right)
    }

    private func mergedTranscriptSegmentText(previous: String, current: String) -> String {
        [
            previous.trimmingCharacters(in: .newlines),
            current.trimmingCharacters(in: .newlines),
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    }

    private func nextTranscriptSpeakerID(existing speakers: [TranscriptSpeaker]) -> String {
        var index = speakers.count + 1
        var candidate = "speaker-\(index)"
        let existingIDs = Set(speakers.map(\.id))

        while existingIDs.contains(candidate) {
            index += 1
            candidate = "speaker-\(index)"
        }

        return candidate
    }

    private func syncMarkdownExportBestEffort(for meeting: Meeting) {
        guard let markdownExporter else {
            return
        }

        try? syncMarkdownExport(for: meeting, using: markdownExporter)
    }

    private func syncMarkdownExport(
        for meeting: Meeting,
        using markdownExporter: any MeetingMarkdownExporting
    ) throws {
        if let transcript = meeting.storedTranscript {
            try markdownExporter.exportTranscript(for: meeting, transcript: transcript)
        } else {
            try markdownExporter.removeTranscript(for: meeting.id)
        }

        if let summary = meeting.summaryText {
            try markdownExporter.exportSummary(for: meeting, summary: summary)
        } else {
            try markdownExporter.removeSummary(for: meeting.id)
        }
    }
}
