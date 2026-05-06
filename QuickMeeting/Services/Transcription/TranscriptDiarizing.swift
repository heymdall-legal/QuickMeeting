//
//  TranscriptDiarizing.swift
//  QuickMeeting
//
//  Created by Codex on 06.05.2026.
//

import Foundation
import SpeakerKit
import WhisperKit

struct TranscriptDiarizationRequest: Sendable {
    let audioFileURL: URL
    let result: TranscriptionResult
}

protocol TranscriptDiarizing: Sendable {
    func diarize(_ request: TranscriptDiarizationRequest) async throws -> StoredTranscript
}

protocol TranscriptAudioLoading: Sendable {
    func loadAudioSamples(from audioFileURL: URL) throws -> [Float]
}

protocol SpeakerDiarizationPerforming: Sendable {
    func diarize(audioSamples: [Float]) async throws -> DiarizationResult
}

struct DefaultTranscriptDiarizer: TranscriptDiarizing {
    private let audioLoader: any TranscriptAudioLoading
    private let diarizationPerformer: any SpeakerDiarizationPerforming

    init(
        audioLoader: (any TranscriptAudioLoading)? = nil,
        diarizationPerformer: (any SpeakerDiarizationPerforming)? = nil
    ) {
        self.audioLoader = audioLoader ?? WhisperKitTranscriptAudioLoader()
        self.diarizationPerformer = diarizationPerformer ?? SpeakerKitDiarizationPerformer()
    }

    func diarize(_ request: TranscriptDiarizationRequest) async throws -> StoredTranscript {
        let audioSamples = try audioLoader.loadAudioSamples(from: request.audioFileURL)
        let diarizationResult = try await diarizationPerformer.diarize(audioSamples: audioSamples)

        return makeStoredTranscript(
            from: request.result.segments,
            diarizationSegments: diarizationResult.segments
        )
    }

    private func makeStoredTranscript(
        from segments: [TranscriptSegment],
        diarizationSegments: [SpeakerSegment]
    ) -> StoredTranscript {
        let orderedDiarizationSegments = diarizationSegments.sorted { lhs, rhs in
            lhs.startTime < rhs.startTime
        }
        let defaultRawSpeakerID = orderedDiarizationSegments.first?.speaker.speakerId ?? 0
        var previousRawSpeakerID: Int?
        var speakerIDsByRawID = [Int: String]()
        var orderedSpeakerIDs = [String]()

        let resolvedSegments = segments.map { segment in
            let rawSpeakerID =
                bestSpeakerID(for: segment, in: orderedDiarizationSegments)
                ?? previousRawSpeakerID
                ?? defaultRawSpeakerID
            previousRawSpeakerID = rawSpeakerID

            let speakerID: String
            if let existingSpeakerID = speakerIDsByRawID[rawSpeakerID] {
                speakerID = existingSpeakerID
            } else {
                let newSpeakerID = "speaker-\(orderedSpeakerIDs.count + 1)"
                speakerIDsByRawID[rawSpeakerID] = newSpeakerID
                orderedSpeakerIDs.append(newSpeakerID)
                speakerID = newSpeakerID
            }

            return TranscriptSegment(
                id: segment.id,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                speakerID: speakerID
            )
        }

        if orderedSpeakerIDs.isEmpty {
            orderedSpeakerIDs = ["speaker-1"]
        }

        let speakers = orderedSpeakerIDs.enumerated().map { index, speakerID in
            TranscriptSpeaker(id: speakerID, displayName: "Speaker \(index + 1)")
        }

        return StoredTranscript(speakers: speakers, segments: resolvedSegments)
    }

    private func bestSpeakerID(
        for transcriptSegment: TranscriptSegment,
        in diarizationSegments: [SpeakerSegment]
    ) -> Int? {
        guard
            let startTime = transcriptSegment.startTime,
            let endTime = transcriptSegment.endTime
        else {
            return nil
        }

        var bestSpeakerID: Int?
        var bestOverlap: TimeInterval = 0

        for diarizationSegment in diarizationSegments {
            guard let speakerID = diarizationSegment.speaker.speakerId else {
                continue
            }

            let overlap = min(endTime, TimeInterval(diarizationSegment.endTime))
                - max(startTime, TimeInterval(diarizationSegment.startTime))
            guard overlap > 0 else {
                continue
            }

            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeakerID = speakerID
            }
        }

        return bestSpeakerID
    }
}

struct WhisperKitTranscriptAudioLoader: TranscriptAudioLoading {
    func loadAudioSamples(from audioFileURL: URL) throws -> [Float] {
        let audioBuffer = try AudioProcessor.loadAudio(fromPath: audioFileURL.path)
        return AudioProcessor.convertBufferToArray(buffer: audioBuffer)
    }
}

actor SpeakerKitDiarizationPerformer: SpeakerDiarizationPerforming {
    private let downloadBaseURL: URL
    private var speakerKit: SpeakerKit?

    init(
        fileManager: FileManager = .default,
        downloadBaseURL: URL? = nil
    ) {
        self.downloadBaseURL = downloadBaseURL ?? Self.defaultDownloadBaseURL(fileManager: fileManager)
    }

    func diarize(audioSamples: [Float]) async throws -> DiarizationResult {
        let speakerKit = try await resolveSpeakerKit()
        return try await speakerKit.diarize(audioArray: audioSamples)
    }

    private func resolveSpeakerKit() async throws -> SpeakerKit {
        if let speakerKit {
            return speakerKit
        }

        let config = PyannoteConfig(
            downloadBase: downloadBaseURL.path,
            download: true,
            load: false,
            verbose: false
        )
        let speakerKit = try await SpeakerKit(config)
        self.speakerKit = speakerKit
        return speakerKit
    }

    private static func defaultDownloadBaseURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return applicationSupportURL
            .appendingPathComponent("QuickMeeting", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("SpeakerKit", isDirectory: true)
    }
}
