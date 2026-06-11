//
//  KnownSpeakerJSONWriter.swift
//  QuickMeeting
//
//  Created by Codex on 11.06.2026.
//

import Foundation

struct KnownSpeakerExport: Codable, Equatable, Sendable {
    let id: String
    let centroids: [[Double]]
}

struct KnownSpeakerJSONWriter {
    let fileManager: FileManager
    let encoder: JSONEncoder

    init(fileManager: FileManager = .default, encoder: JSONEncoder = JSONEncoder()) {
        self.fileManager = fileManager
        self.encoder = encoder
    }

    func write(speakers: [KnownSpeakerExport], directoryURL: URL) throws -> URL {
        let outputURL = directoryURL.appendingPathComponent("known-speakers-\(UUID().uuidString).json")
        let data = try encoder.encode(speakers)
        fileManager.createFile(atPath: outputURL.path, contents: data)
        return outputURL
    }
}
