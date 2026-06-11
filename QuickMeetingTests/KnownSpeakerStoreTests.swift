import Foundation
import SwiftData
import Testing
@testable import QuickMeeting

@MainActor
struct KnownSpeakerStoreTests {
    @Test
    func findOrCreateReusesExactNameCaseInsensitively() throws {
        let harness = try KnownSpeakerStoreHarness()
        let first = try harness.store.findOrCreateSpeaker(
            named: "Alice Johnson",
            now: .now
        )
        let second = try harness.store.findOrCreateSpeaker(
            named: "  alice johnson  ",
            now: .now
        )

        #expect(first.id == second.id)
        #expect(try harness.fetchKnownSpeakers().count == 1)
    }

    @Test
    func appendCentroidPrunesOldestWhenCapacityExceedsThree() throws {
        let harness = try KnownSpeakerStoreHarness()
        let speaker = try harness.store.findOrCreateSpeaker(named: "Alice", now: .now)

        try harness.store.appendCentroid(
            [0.1],
            to: speaker.id,
            sourceMeetingID: nil,
            sourceSpeakerID: nil,
            now: Date(timeIntervalSince1970: 10)
        )
        try harness.store.appendCentroid(
            [0.2],
            to: speaker.id,
            sourceMeetingID: nil,
            sourceSpeakerID: nil,
            now: Date(timeIntervalSince1970: 20)
        )
        try harness.store.appendCentroid(
            [0.3],
            to: speaker.id,
            sourceMeetingID: nil,
            sourceSpeakerID: nil,
            now: Date(timeIntervalSince1970: 30)
        )
        try harness.store.appendCentroid(
            [0.4],
            to: speaker.id,
            sourceMeetingID: nil,
            sourceSpeakerID: nil,
            now: Date(timeIntervalSince1970: 40)
        )

        let reloaded = try harness.fetchKnownSpeakers().first
        #expect(reloaded?.centroids.map(\.values) == [[0.2], [0.3], [0.4]])
    }
}

@MainActor
private struct KnownSpeakerStoreHarness {
    let container: ModelContainer
    let store: KnownSpeakerStore

    init() throws {
        let schema = Schema([
            Meeting.self,
            PersistedTranscriptSpeaker.self,
            PersistedTranscriptSegment.self,
            PersistedKnownSpeaker.self,
            PersistedKnownSpeakerCentroid.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        store = KnownSpeakerStore(modelContext: ModelContext(container))
    }

    func fetchKnownSpeakers() throws -> [PersistedKnownSpeaker] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<PersistedKnownSpeaker>())
    }
}
