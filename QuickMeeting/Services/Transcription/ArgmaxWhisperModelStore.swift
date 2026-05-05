//
//  ArgmaxWhisperModelStore.swift
//  QuickMeeting
//
//  Created by Codex on 05.05.2026.
//

import Foundation
import ArgmaxCore
import WhisperKit

struct InstalledTranscriptionModel: Equatable {
    let sizeInBytes: Int64
    let installedAt: Date?
}

protocol WhisperModelStore {
    func installedModels() async throws -> [TranscriptionModelID: InstalledTranscriptionModel]
    func downloadModel(
        _ model: TranscriptionModel,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws
    func deleteModel(_ model: TranscriptionModel) async throws
}

struct ArgmaxWhisperModelStore: WhisperModelStore {
    let fileManager: FileManager
    let downloadBaseURL: URL
    let modelRepositoryID: String

    init(
        fileManager: FileManager = .default,
        downloadBaseURL: URL? = nil,
        modelRepositoryID: String = "argmaxinc/whisperkit-coreml"
    ) {
        self.fileManager = fileManager
        self.downloadBaseURL = downloadBaseURL ?? Self.defaultDownloadBaseURL(fileManager: fileManager)
        self.modelRepositoryID = modelRepositoryID
    }

    func installedModels() async throws -> [TranscriptionModelID: InstalledTranscriptionModel] {
        var installed = [TranscriptionModelID: InstalledTranscriptionModel]()

        for model in TranscriptionModelCatalog.supportedModels {
            guard let modelURL = try findInstalledModelURL(for: model) else {
                continue
            }

            installed[model.id] = InstalledTranscriptionModel(
                sizeInBytes: try directorySize(at: modelURL),
                installedAt: try fileManager.attributesOfItem(atPath: modelURL.path)[.creationDate] as? Date
            )
        }

        return installed
    }

    func downloadModel(
        _ model: TranscriptionModel,
        onProgress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        _ = try await WhisperKit.download(
            variant: model.argmaxModelID,
            downloadBase: downloadBaseURL,
            progressCallback: { progress in
                onProgress(progress.fractionCompleted)
            }
        )
    }

    func deleteModel(_ model: TranscriptionModel) async throws {
        guard let modelURL = try findInstalledModelURL(for: model) else {
            return
        }

        try fileManager.removeItem(at: modelURL)
    }

    private func findInstalledModelURL(for model: TranscriptionModel) throws -> URL? {
        let repoRootURL = HubApiWrapper(downloadBase: downloadBaseURL)
            .localRepoLocation(.init(id: modelRepositoryID))

        guard fileManager.fileExists(atPath: repoRootURL.path) else {
            return nil
        }

        let modelPrefix = "openai_whisper-\(model.argmaxModelID)"
        let enumerator = fileManager.enumerator(
            at: repoRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                continue
            }

            if url.lastPathComponent == modelPrefix {
                return url
            }
        }

        return nil
    }

    private func directorySize(at directoryURL: URL) throws -> Int64 {
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var totalSize: Int64 = 0

        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                continue
            }

            totalSize += Int64(values.fileSize ?? 0)
        }

        return totalSize
    }

    private static func defaultDownloadBaseURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return applicationSupportURL
            .appendingPathComponent("QuickMeeting", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }
}
