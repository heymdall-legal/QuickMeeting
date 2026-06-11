import Foundation

struct SidecarTranscriptionEventDecoder {
    private let decoder = JSONDecoder()

    func decode(line: String) throws -> SidecarTranscriptionEvent? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }

        let statusEnvelope: SidecarStatusEnvelope
        do {
            statusEnvelope = try decoder.decode(SidecarStatusEnvelope.self, from: data)
        } catch {
            return nil
        }

        switch statusEnvelope.status {
        case "running":
            return .running
        case "downloading":
            return .downloading(try decoder.decode(SidecarDownloadingEnvelope.self, from: data).progress)
        case "transcribing":
            return .transcribing(try decoder.decode(SidecarTranscribingEnvelope.self, from: data).progress)
        case "diarization":
            return .diarization(try decoder.decode(SidecarDiarizationEnvelope.self, from: data).progress)
        case "completed":
            return .completed(try decoder.decode(SidecarCompletedEnvelope.self, from: data).payload)
        case "error":
            return .error(try decoder.decode(SidecarErrorEnvelope.self, from: data).payload)
        default:
            return nil
        }
    }
}

private struct SidecarStatusEnvelope: Codable {
    let status: String
}

private struct SidecarDownloadingEnvelope: Codable {
    let status: String
    let percent: Int
    let file: String?
    let bytesDownloaded: Int?
    let bytesTotal: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case percent
        case file
        case bytesDownloaded = "bytes_downloaded"
        case bytesTotal = "bytes_total"
    }

    var progress: SidecarDownloadProgress {
        SidecarDownloadProgress(
            percent: percent,
            file: file,
            bytesDownloaded: bytesDownloaded,
            bytesTotal: bytesTotal
        )
    }
}

private struct SidecarTranscribingEnvelope: Codable {
    let status: String
    let percent: Int

    var progress: SidecarPercentProgress {
        SidecarPercentProgress(percent: percent)
    }
}

private struct SidecarDiarizationEnvelope: Decodable {
    let status: String
    let step: String
    let percent: Int

    enum CodingKeys: String, CodingKey {
        case status
        case step
        case stepName = "step_name"
        case percent
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        percent = try container.decode(Int.self, forKey: .percent)
        step = try container.decodeIfPresent(String.self, forKey: .step)
            ?? container.decode(String.self, forKey: .stepName)
    }

    var progress: SidecarDiarizationProgress {
        SidecarDiarizationProgress(step: step, percent: percent)
    }
}

private struct SidecarCompletedEnvelope: Codable {
    let status: String
    let speakers: [SidecarCompletedSpeaker]
    let segments: [SidecarCompletedSegment]

    var payload: SidecarCompletedPayload {
        SidecarCompletedPayload(speakers: speakers, segments: segments)
    }
}

private struct SidecarErrorEnvelope: Codable {
    let status: String
    let reason: String

    var payload: SidecarErrorPayload {
        SidecarErrorPayload(reason: reason)
    }
}
