import Foundation

enum MeetingTranscriptContent: Equatable {
    case text(String)
    case notAvailable
    case unavailable(message: String)
}

enum MeetingTranscriptSpeakersContent: Equatable {
    case available([TranscriptSpeaker])
    case unavailable
}

func meetingDetailReloadKey(for meeting: Meeting) -> String {
    [
        meeting.id.uuidString,
        meeting.audioFilePath,
        meeting.transcriptFilePath ?? "",
        String(meeting.updatedAt.timeIntervalSinceReferenceDate)
    ].joined(separator: "|")
}

func loadMeetingTranscriptContent(
    from transcriptFilePath: String?,
    fileManager: FileManager = .default
) throws -> MeetingTranscriptContent {
    guard let transcriptFilePath else {
        return .notAvailable
    }

    guard let resolvedTranscriptPath = resolveTranscriptFilePath(
        transcriptFilePath,
        fileManager: fileManager
    ) else {
        return .unavailable(message: "Transcript file is unavailable.")
    }

    do {
        let transcriptText = try String(contentsOfFile: resolvedTranscriptPath, encoding: .utf8)
        return .text(transcriptText)
    } catch {
        return .unavailable(message: "Transcript file is unavailable.")
    }
}

func loadMeetingTranscriptSpeakers(
    from transcriptFilePath: String?,
    fileManager: FileManager = .default
) -> MeetingTranscriptSpeakersContent {
    guard let transcriptFilePath,
          let resolvedTranscriptPath = resolveTranscriptFilePath(
              transcriptFilePath,
              fileManager: fileManager
          )
    else {
        return .unavailable
    }

    let transcriptURL = URL(fileURLWithPath: resolvedTranscriptPath)
    let meetingFolderURL = transcriptURL.deletingLastPathComponent()
    let transcriptStore = MeetingTranscriptStore(fileManager: fileManager)

    do {
        let transcript = try transcriptStore.loadTranscript(in: meetingFolderURL)
        return .available(transcript.speakers)
    } catch {
        return .unavailable
    }
}

private func resolveTranscriptFilePath(
    _ transcriptFilePath: String,
    fileManager: FileManager
) -> String? {
    if fileManager.fileExists(atPath: transcriptFilePath) {
        return transcriptFilePath
    }

    let decodedPath = URL(fileURLWithPath: transcriptFilePath).path(percentEncoded: false)
    if fileManager.fileExists(atPath: decodedPath) {
        return decodedPath
    }

    if let removingPercentEncoding = transcriptFilePath.removingPercentEncoding,
       fileManager.fileExists(atPath: removingPercentEncoding) {
        return removingPercentEncoding
    }

    return nil
}
