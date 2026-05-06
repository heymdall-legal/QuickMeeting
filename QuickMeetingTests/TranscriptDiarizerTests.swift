import Foundation
import SpeakerKit
import Testing
@testable import QuickMeeting

@MainActor
struct TranscriptDiarizerTests {
    @Test
    func diarizeAssignsSpeakerIDsFromSpeakerKitSegments() async throws {
        let diarizer = DefaultTranscriptDiarizer(
            audioLoader: StubTranscriptAudioLoader(result: .success([0, 1, 2])),
            diarizationPerformer: StubSpeakerDiarizationPerformer(result: .success(
                DiarizationResult(
                    speakerCount: 2,
                    totalFrames: 32000,
                    frameRate: 100,
                    segments: [
                        SpeakerSegment(speaker: .speakerId(0), startTime: 0, endTime: 1.4, frameRate: 100),
                        SpeakerSegment(speaker: .speakerId(1), startTime: 1.4, endTime: 3.2, frameRate: 100),
                    ]
                )
            ))
        )
        let request = TranscriptDiarizationRequest(
            audioFileURL: URL(fileURLWithPath: "/tmp/meeting.wav"),
            result: TranscriptionResult(
                fullText: "Hello\nHi",
                segments: [
                    TranscriptSegment(text: "Hello", startTime: 0.0, endTime: 1.2),
                    TranscriptSegment(text: "Hi", startTime: 1.6, endTime: 2.5),
                ]
            )
        )

        let transcript = try await diarizer.diarize(request)

        #expect(transcript.speakers == [
            TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
            TranscriptSpeaker(id: "speaker-2", displayName: "Speaker 2"),
        ])
        #expect(transcript.segments.map { $0.speakerID } == ["speaker-1", "speaker-2"])
    }

    @Test
    func diarizeUsesPreviousSpeakerWhenSegmentHasNoDirectOverlap() async throws {
        let diarizer = DefaultTranscriptDiarizer(
            audioLoader: StubTranscriptAudioLoader(result: .success([0, 1, 2])),
            diarizationPerformer: StubSpeakerDiarizationPerformer(result: .success(
                DiarizationResult(
                    speakerCount: 1,
                    totalFrames: 16000,
                    frameRate: 100,
                    segments: [
                        SpeakerSegment(speaker: .speakerId(0), startTime: 0, endTime: 1.0, frameRate: 100),
                    ]
                )
            ))
        )
        let request = TranscriptDiarizationRequest(
            audioFileURL: URL(fileURLWithPath: "/tmp/meeting.wav"),
            result: TranscriptionResult(
                fullText: "Hello\nContinuation",
                segments: [
                    TranscriptSegment(text: "Hello", startTime: 0.0, endTime: 0.8),
                    TranscriptSegment(text: "Continuation", startTime: 1.5, endTime: 2.0),
                ]
            )
        )

        let transcript = try await diarizer.diarize(request)

        #expect(transcript.segments.map { $0.speakerID } == ["speaker-1", "speaker-1"])
        #expect(transcript.speakers == [
            TranscriptSpeaker(id: "speaker-1", displayName: "Speaker 1"),
        ])
    }
}

private struct StubTranscriptAudioLoader: TranscriptAudioLoading {
    let result: Result<[Float], Error>

    func loadAudioSamples(from audioFileURL: URL) throws -> [Float] {
        _ = audioFileURL
        return try result.get()
    }
}

private actor StubSpeakerDiarizationPerformer: SpeakerDiarizationPerforming {
    let result: Result<DiarizationResult, Error>

    init(result: Result<DiarizationResult, Error>) {
        self.result = result
    }

    func diarize(audioSamples: [Float]) async throws -> DiarizationResult {
        _ = audioSamples
        return try result.get()
    }
}
