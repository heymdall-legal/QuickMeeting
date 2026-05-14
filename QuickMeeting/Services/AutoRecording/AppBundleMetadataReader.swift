//
//  AppBundleMetadataReader.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import Foundation

enum AppBundleMetadataReaderError: LocalizedError, Equatable {
    case invalidApplication
    case missingBundleIdentifier
    case unreadableMetadata

    var errorDescription: String? {
        switch self {
        case .invalidApplication:
            return "Selected item is not a valid application."
        case .missingBundleIdentifier:
            return "Selected app has no bundle identifier."
        case .unreadableMetadata:
            return "Couldn't read app metadata."
        }
    }
}

protocol AppBundleMetadataReading: Sendable {
    func readMetadata(at url: URL) throws -> AppBundleMetadata
}

struct NativeAppBundleMetadataReader: AppBundleMetadataReading {
    func readMetadata(at url: URL) throws -> AppBundleMetadata {
        guard url.pathExtension == "app",
              let bundle = Bundle(url: url) else {
            throw AppBundleMetadataReaderError.invalidApplication
        }

        guard let bundleIdentifier = bundle.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            throw AppBundleMetadataReaderError.missingBundleIdentifier
        }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        return AppBundleMetadata(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            appPath: url.path
        )
    }
}
