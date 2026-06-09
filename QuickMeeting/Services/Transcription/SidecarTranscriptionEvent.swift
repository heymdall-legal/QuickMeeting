import Foundation

enum SidecarTranscriptionEvent: Equatable, Sendable {
    case running
    case downloading(SidecarDownloadProgress)
    case transcribing(SidecarPercentProgress)
    case diarization(SidecarDiarizationProgress)
    case completed(SidecarCompletedPayload)
    case error(SidecarErrorPayload)
}

struct SidecarDownloadProgress: Codable, Equatable, Sendable {
    let percent: Int
    let file: String?
    let bytesDownloaded: Int?
    let bytesTotal: Int?
}

struct SidecarPercentProgress: Codable, Equatable, Sendable {
    let percent: Int
}

struct SidecarDiarizationProgress: Codable, Equatable, Sendable {
    let step: String
    let percent: Int
}

struct SidecarCompletedPayload: Codable, Equatable, Sendable {
    let speakers: [SidecarCompletedSpeaker]
    let segments: [SidecarCompletedSegment]
}

struct SidecarCompletedSpeaker: Codable, Equatable, Sendable {
    let id: String
    let matchedID: String?
    let probability: Double?
    let centroid: [Double]?

    enum CodingKeys: String, CodingKey {
        case id
        case matchedID = "matched_id"
        case probability
        case centroid
    }
}

struct SidecarCompletedSegment: Codable, Equatable, Sendable {
    let speaker: String
    let start: Double
    let end: Double
    let text: String
}

struct SidecarErrorPayload: Codable, Equatable, Sendable {
    let reason: String
}
