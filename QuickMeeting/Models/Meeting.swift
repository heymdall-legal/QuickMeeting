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
    private(set) var transcriptPreview: String?
    @Relationship(deleteRule: .cascade) private(set) var transcriptSpeakers: [PersistedTranscriptSpeaker]
    @Relationship(deleteRule: .cascade) private(set) var transcriptSegments: [PersistedTranscriptSegment]
    private var rawTranscriptData: Data?
    private var correctedTranscriptData: Data?
    private var transcriptionPipelineMetadataData: Data?
    private(set) var summaryText: String?
    private(set) var duration: TimeInterval?
    private(set) var calendarEventID: String?
    @Attribute(originalName: "attendeeNames") private var attendeeNamesStorage: [String]?
    private(set) var createdAt: Date
    private(set) var updatedAt: Date
    private(set) var waveformSamples: [Double]?

    var status: MeetingStatus {
        get throws {
            guard let status = MeetingStatus(rawValue: statusRawValue) else {
                throw MeetingError.invalidStatusRawValue(statusRawValue)
            }

            return status
        }
    }

    var storedTranscript: StoredTranscript? {
        if !transcriptSpeakers.isEmpty || !transcriptSegments.isEmpty {
            return finalStoredTranscript
        }

        return onlineDraftStoredTranscript
    }

    var finalStoredTranscript: StoredTranscript? {
        guard !transcriptSpeakers.isEmpty || !transcriptSegments.isEmpty else { return nil }
        return StoredTranscript(
            speakers: transcriptSpeakers.map(\.value),
            segments: transcriptSegments
                .sorted(by: Self.arePersistedTranscriptSegmentsInDisplayOrder)
                .map(\.value)
        )
    }

    var onlineDraftStoredTranscript: StoredTranscript? {
        transcriptArtifactEnvelope?.onlineDraft?.storedTranscript
    }

    var transcriptLifecycleState: TranscriptLifecycleState? {
        transcriptArtifactEnvelope?.lifecycleState
    }

    var attendeeNames: [String] {
        attendeeNamesStorage ?? []
    }

    var rawStoredTranscript: StoredTranscript? {
        Self.decode(StoredTranscript.self, from: rawTranscriptData)
    }

    var correctedStoredTranscript: StoredTranscript? {
        Self.decode(StoredTranscript.self, from: correctedTranscriptData)
    }

    var transcriptionPipelineMetadata: TranscriptionPipelineMetadata? {
        transcriptArtifactEnvelope?.finalMetadata
    }

    private var transcriptArtifactEnvelope: TranscriptArtifactEnvelope? {
        if let envelope = Self.decode(
            TranscriptArtifactEnvelope.self,
            from: transcriptionPipelineMetadataData
        ) {
            return envelope
        }
        guard let legacy = Self.decode(
            TranscriptionPipelineMetadata.self,
            from: transcriptionPipelineMetadataData
        ) else {
            return nil
        }
        return TranscriptArtifactEnvelope(
            lifecycleState: .finalAvailable,
            visibleVersion: .final,
            finalMetadata: legacy
        )
    }

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        status: MeetingStatus,
        audioFilePath: String,
        transcriptPreview: String? = nil,
        transcriptSpeakers: [PersistedTranscriptSpeaker] = [],
        transcriptSegments: [PersistedTranscriptSegment] = [],
        summaryText: String? = nil,
        duration: TimeInterval? = nil,
        calendarEventID: String? = nil,
        attendeeNames: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.statusRawValue = status.rawValue
        self.audioFilePath = audioFilePath
        self.transcriptPreview = transcriptPreview
        self.transcriptSpeakers = transcriptSpeakers
        self.transcriptSegments = transcriptSegments
        self.summaryText = summaryText
        self.duration = duration
        self.calendarEventID = calendarEventID
        attendeeNamesStorage = attendeeNames
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func setStatus(_ newStatus: MeetingStatus, updatedAt: Date = Date()) {
        statusRawValue = newStatus.rawValue
        touch(updatedAt: updatedAt)
    }

    func renameTitle(to newTitle: String, updatedAt: Date = Date()) {
        title = newTitle
        touch(updatedAt: updatedAt)
    }

    func updateCalendarEvent(
        title newTitle: String,
        attendeeNames: [String],
        calendarEventID: String?,
        updatedAt: Date = Date()
    ) {
        title = newTitle
        attendeeNamesStorage = attendeeNames
        self.calendarEventID = calendarEventID
        touch(updatedAt: updatedAt)
    }

    func finishRecording(endedAt: Date, duration: TimeInterval, updatedAt: Date = Date()) {
        self.endedAt = endedAt
        self.duration = duration
        statusRawValue = MeetingStatus.recorded.rawValue
        touch(updatedAt: updatedAt)
    }

    func beginTranscription(updatedAt: Date = Date()) {
        // The published final stays visible while a replacement job runs.
        // Runtime progress represents the in-flight job; no persisted artifact
        // is mutated until completeTranscription commits the replacement.
        var envelope = transcriptArtifactEnvelope ?? TranscriptArtifactEnvelope(
            lifecycleState: .finalizing,
            visibleVersion: finalStoredTranscript == nil ? .draft : .final
        )
        envelope.lifecycleState = .finalizing
        transcriptionPipelineMetadataData = Self.encode(envelope)
        touch(updatedAt: updatedAt)
    }

    func completeTranscription(
        transcript: StoredTranscript,
        transcriptPreview: String,
        rawTranscript: StoredTranscript? = nil,
        correctedTranscript: StoredTranscript? = nil,
        pipelineMetadata: TranscriptionPipelineMetadata? = nil,
        updatedAt: Date = Date()
    ) {
        self.transcriptPreview = transcriptPreview
        let orderedSegments = transcript.segments
            .sorted(by: Self.areTranscriptSegmentsInDisplayOrder)
        transcriptSpeakers = transcript.speakers.map(PersistedTranscriptSpeaker.init)
        transcriptSegments = orderedSegments.enumerated().map { index, segment in
            PersistedTranscriptSegment(segment, sortIndex: index)
        }
        rawTranscriptData = Self.encode(rawTranscript)
        correctedTranscriptData = Self.encode(correctedTranscript)
        var envelope = transcriptArtifactEnvelope ?? TranscriptArtifactEnvelope(
            lifecycleState: .finalAvailable,
            visibleVersion: .final
        )
        envelope.lifecycleState = .finalAvailable
        envelope.visibleVersion = .final
        envelope.finalMetadata = pipelineMetadata
        transcriptionPipelineMetadataData = Self.encode(envelope)
        summaryText = nil
        statusRawValue = MeetingStatus.completed.rawValue
        touch(updatedAt: updatedAt)
    }

    func replaceTranscript(
        speakers: [TranscriptSpeaker],
        segments: [TranscriptSegment],
        updatedAt: Date = Date()
    ) {
        transcriptSpeakers = speakers.map(PersistedTranscriptSpeaker.init)
        transcriptSegments = segments.enumerated().map { index, segment in
            PersistedTranscriptSegment(segment, sortIndex: index)
        }
        transcriptPreview = StoredTranscript(speakers: speakers, segments: segments).fullText
        correctedTranscriptData = Self.encode(StoredTranscript(speakers: speakers, segments: segments))
        touch(updatedAt: updatedAt)
    }

    func failTranscription(updatedAt: Date = Date()) {
        var envelope = transcriptArtifactEnvelope ?? TranscriptArtifactEnvelope(
            lifecycleState: .finalFailed,
            visibleVersion: finalStoredTranscript == nil ? .draft : .final
        )
        envelope.lifecycleState = .finalFailed
        envelope.visibleVersion = finalStoredTranscript == nil ? .draft : .final
        transcriptionPipelineMetadataData = Self.encode(envelope)
        statusRawValue = finalStoredTranscript == nil
            ? MeetingStatus.failed.rawValue
            : MeetingStatus.completed.rawValue
        touch(updatedAt: updatedAt)
    }

    func applyTranscriptCorrection(
        _ correctedTranscript: StoredTranscript,
        pipelineMetadata: TranscriptionPipelineMetadata,
        updatedAt: Date = Date()
    ) {
        guard let published = storedTranscript,
              Self.hasIdenticalStructure(published, correctedTranscript) else {
            return
        }
        transcriptPreview = correctedTranscript.fullText
        transcriptSpeakers = published.speakers.map(PersistedTranscriptSpeaker.init)
        transcriptSegments = correctedTranscript.segments.enumerated().map { index, segment in
            PersistedTranscriptSegment(segment, sortIndex: index)
        }
        correctedTranscriptData = Self.encode(correctedTranscript)
        var envelope = transcriptArtifactEnvelope ?? TranscriptArtifactEnvelope(
            lifecycleState: .finalAvailable,
            visibleVersion: .final
        )
        envelope.finalMetadata = pipelineMetadata
        transcriptionPipelineMetadataData = Self.encode(envelope)
        touch(updatedAt: updatedAt)
    }

    func beginOnlineDraft(updatedAt: Date = Date()) {
        var envelope = transcriptArtifactEnvelope ?? TranscriptArtifactEnvelope(
            lifecycleState: .recording,
            visibleVersion: .draft,
            onlineDraft: OnlineDraftTranscript()
        )
        envelope.lifecycleState = .recording
        envelope.visibleVersion = finalStoredTranscript == nil ? .draft : .final
        if envelope.onlineDraft == nil { envelope.onlineDraft = OnlineDraftTranscript() }
        transcriptionPipelineMetadataData = Self.encode(envelope)
        touch(updatedAt: updatedAt)
    }

    func upsertOnlineDraftEvent(_ event: OnlineDraftEvent, updatedAt: Date = Date()) {
        var envelope = transcriptArtifactEnvelope ?? TranscriptArtifactEnvelope(
            lifecycleState: .recording,
            visibleVersion: .draft,
            onlineDraft: OnlineDraftTranscript()
        )
        var draft = envelope.onlineDraft ?? OnlineDraftTranscript()
        draft.upsert(event)
        envelope.onlineDraft = draft
        envelope.visibleVersion = finalStoredTranscript == nil ? .draft : .final
        transcriptionPipelineMetadataData = Self.encode(envelope)
        if finalStoredTranscript == nil {
            transcriptPreview = draft.storedTranscript.fullText
        }
        touch(updatedAt: updatedAt)
    }

    func renameOnlineDraftSpeaker(
        clusterID: String,
        displayName: String,
        updatedAt: Date = Date()
    ) -> Bool {
        guard var envelope = transcriptArtifactEnvelope,
              var draft = envelope.onlineDraft,
              draft.assignSpeakerName(displayName, to: clusterID) else {
            return false
        }
        envelope.onlineDraft = draft
        transcriptionPipelineMetadataData = Self.encode(envelope)
        if finalStoredTranscript == nil {
            transcriptPreview = draft.storedTranscript.fullText
        }
        touch(updatedAt: updatedAt)
        return true
    }

    func finishOnlineDraft(updatedAt: Date = Date()) {
        var envelope = transcriptArtifactEnvelope ?? TranscriptArtifactEnvelope(
            lifecycleState: .draftAvailable,
            visibleVersion: .draft,
            onlineDraft: OnlineDraftTranscript()
        )
        envelope.lifecycleState = .draftAvailable
        envelope.visibleVersion = finalStoredTranscript == nil ? .draft : .final
        transcriptionPipelineMetadataData = Self.encode(envelope)
        touch(updatedAt: updatedAt)
    }

    func storeOnlineDraftTelemetry(
        _ telemetry: OnlineDraftTelemetry,
        updatedAt: Date = Date()
    ) {
        var envelope = transcriptArtifactEnvelope ?? TranscriptArtifactEnvelope(
            lifecycleState: .draftAvailable,
            visibleVersion: finalStoredTranscript == nil ? .draft : .final
        )
        envelope.onlineTelemetry = telemetry
        transcriptionPipelineMetadataData = Self.encode(envelope)
        touch(updatedAt: updatedAt)
    }

    func updateTranscriptionPipelineMetadata(
        _ metadata: TranscriptionPipelineMetadata,
        updatedAt: Date = Date()
    ) {
        var envelope = transcriptArtifactEnvelope ?? TranscriptArtifactEnvelope(
            lifecycleState: .finalAvailable,
            visibleVersion: .final
        )
        envelope.finalMetadata = metadata
        transcriptionPipelineMetadataData = Self.encode(envelope)
        touch(updatedAt: updatedAt)
    }

    func storeWaveform(_ samples: [Double], updatedAt: Date = Date()) {
        waveformSamples = samples
        touch(updatedAt: updatedAt)
    }

    func storeSummary(_ summary: String, updatedAt: Date = Date()) {
        summaryText = summary
        touch(updatedAt: updatedAt)
    }

    private func touch(updatedAt: Date) {
        self.updatedAt = updatedAt
    }

    private static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func hasIdenticalStructure(
        _ published: StoredTranscript,
        _ corrected: StoredTranscript
    ) -> Bool {
        guard published.speakers == corrected.speakers,
              published.segments.count == corrected.segments.count else {
            return false
        }
        return zip(published.segments, corrected.segments).allSatisfy { original, replacement in
            original.id == replacement.id
                && original.startTime == replacement.startTime
                && original.endTime == replacement.endTime
                && original.speakerID == replacement.speakerID
        }
    }

    private static func arePersistedTranscriptSegmentsInDisplayOrder(
        _ lhs: PersistedTranscriptSegment,
        _ rhs: PersistedTranscriptSegment
    ) -> Bool {
        switch (lhs.sortIndex, rhs.sortIndex) {
        case let (lhsIndex?, rhsIndex?) where lhsIndex != rhsIndex:
            return lhsIndex < rhsIndex
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return areTranscriptSegmentsInDisplayOrder(lhs.value, rhs.value)
        }
    }

    private static func areTranscriptSegmentsInDisplayOrder(
        _ lhs: TranscriptSegment,
        _ rhs: TranscriptSegment
    ) -> Bool {
        switch (lhs.startTime, rhs.startTime) {
        case let (lhsStart?, rhsStart?) where lhsStart != rhsStart:
            return lhsStart < rhsStart
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }

        switch (lhs.endTime, rhs.endTime) {
        case let (lhsEnd?, rhsEnd?) where lhsEnd != rhsEnd:
            return lhsEnd < rhsEnd
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }

        if lhs.text != rhs.text {
            return lhs.text < rhs.text
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}
