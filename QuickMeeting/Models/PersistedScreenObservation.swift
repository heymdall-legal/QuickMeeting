//
//  PersistedScreenObservation.swift
//  QuickMeeting
//

import Foundation
import SwiftData

@Model
final class PersistedScreenObservation {
    @Attribute(.unique) var id: UUID
    var meetingID: UUID
    var capturedAtOffset: TimeInterval
    var imageRelativePath: String
    var thumbnailRelativePath: String?
    var sourceAppBundleID: String?
    var sourceWindowTitle: String?
    private var textBoxesData: Data?
    private var activeTileData: Data?

    init(_ value: ScreenObservation) {
        id = value.id
        meetingID = value.meetingID
        capturedAtOffset = value.capturedAtOffset
        imageRelativePath = value.imageRelativePath
        thumbnailRelativePath = value.thumbnailRelativePath
        sourceAppBundleID = value.sourceAppBundleID
        sourceWindowTitle = value.sourceWindowTitle
        textBoxesData = try? JSONEncoder().encode(value.textBoxes)
        activeTileData = try? JSONEncoder().encode(value.activeTile)
    }

    var value: ScreenObservation {
        ScreenObservation(
            id: id,
            meetingID: meetingID,
            capturedAtOffset: capturedAtOffset,
            imageRelativePath: imageRelativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            sourceAppBundleID: sourceAppBundleID,
            sourceWindowTitle: sourceWindowTitle,
            textBoxes: Self.decode([ScreenTextObservation].self, from: textBoxesData) ?? [],
            activeTile: Self.decode(ScreenTileObservation.self, from: activeTileData)
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
