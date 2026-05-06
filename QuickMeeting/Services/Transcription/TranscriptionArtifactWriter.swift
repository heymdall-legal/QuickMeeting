//
//  TranscriptionArtifactWriter.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Foundation

struct TranscriptionArtifacts: Equatable {
    let transcriptFileURL: URL
    let sidecarFileURL: URL
    let previewText: String
}

struct TranscriptionArtifactWriter {
    let fileManager: FileManager
    private let encoder = JSONEncoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writeArtifacts(
        for transcript: StoredTranscript,
        in meetingFolderURL: URL
    ) throws -> TranscriptionArtifacts {
        let sidecarFileURL = meetingFolderURL.appendingPathComponent("transcript.json")
        let transcriptFileURL = meetingFolderURL.appendingPathComponent("transcript.md")
        let sidecarData = try encoder.encode(transcript)
        let markdown = renderMarkdown(from: transcript)

        try sidecarData.write(to: sidecarFileURL, options: .atomic)
        try markdown.write(to: transcriptFileURL, atomically: true, encoding: .utf8)

        return TranscriptionArtifacts(
            transcriptFileURL: transcriptFileURL,
            sidecarFileURL: sidecarFileURL,
            previewText: makePreviewText(from: transcript)
        )
    }

    func renderMarkdown(from transcript: StoredTranscript) -> String {
        let speakerNames = Dictionary(uniqueKeysWithValues: transcript.speakers.map { ($0.id, $0.displayName) })
        var blocks: [(speakerName: String, lines: [String])] = []

        for segment in transcript.segments {
            let line = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let speakerName = speakerNames[segment.speakerID ?? ""] ?? "Speaker"
            if blocks.last?.speakerName == speakerName {
                blocks[blocks.count - 1].lines.append(line)
            } else {
                blocks.append((speakerName: speakerName, lines: [line]))
            }
        }

        return blocks
            .map { block in
                "## \(block.speakerName)\n" + block.lines.joined(separator: "\n\n")
            }
            .joined(separator: "\n\n")
    }

    func makePreviewText(from transcript: StoredTranscript) -> String {
        transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
