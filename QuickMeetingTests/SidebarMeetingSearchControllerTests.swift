import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct SidebarMeetingSearchControllerTests {
    @Test
    func latestQueryWinsWhenEarlierSearchCompletesLater() async {
        let firstMeeting = makeMeeting(
            title: "Design Review",
            segments: [
                PersistedTranscriptSegment(
                    TranscriptSegment(text: "Roadmap notes", speakerID: "speaker-1")
                )
            ]
        )
        let secondMeeting = makeMeeting(
            title: "Roadmap Planning",
            segments: [
                PersistedTranscriptSegment(
                    TranscriptSegment(text: "Design discussion", speakerID: "speaker-1")
                )
            ]
        )
        let search = ControlledSearch()
        let controller = SidebarMeetingSearchController { documents, query in
            await search.run(documents: documents, query: query)
        }

        controller.replaceMeetings([firstMeeting, secondMeeting])
        controller.updateQuery("design")
        await search.waitUntilStarted(query: "design")

        controller.updateQuery("roadmap")
        await search.waitUntilStarted(query: "roadmap")

        await search.finish(query: "roadmap")
        await waitForMatchingMeetingIDs(
            on: controller,
            toEqual: Set([firstMeeting.id, secondMeeting.id])
        )

        await search.finish(query: "design")
        await Task.yield()

        #expect(controller.matchingMeetingIDs == Set([firstMeeting.id, secondMeeting.id]))
    }

    private func makeMeeting(
        title: String,
        speakers: [PersistedTranscriptSpeaker] = [],
        segments: [PersistedTranscriptSegment] = []
    ) -> Meeting {
        Meeting(
            title: title,
            startedAt: Date(timeIntervalSince1970: 1_714_561_200),
            status: .completed,
            audioFilePath: "/tmp/audio.wav",
            transcriptSpeakers: speakers,
            transcriptSegments: segments
        )
    }

    private func waitForMatchingMeetingIDs(
        on controller: SidebarMeetingSearchController,
        toEqual expected: Set<UUID>
    ) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))

        while controller.matchingMeetingIDs != expected {
            if ContinuousClock.now >= deadline {
                Issue.record("Timed out waiting for search results \(expected)")
                return
            }

            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor ControlledSearch {
    private var startedQueries = Set<String>()
    private var waitersByQuery = [String: [CheckedContinuation<Void, Never>]]()
    private var finishContinuations = [String: CheckedContinuation<Void, Never>]()

    func run(documents: [MeetingSearchDocument], query: String) async -> Set<UUID> {
        startedQueries.insert(query)
        resumeWaiters(for: query)

        await withCheckedContinuation { continuation in
            finishContinuations[query] = continuation
        }

        return Set(
            documents
                .filter { meetingSearchDocumentMatchesSearch($0, query: query) }
                .map(\.id)
        )
    }

    func waitUntilStarted(query: String) async {
        if startedQueries.contains(query) {
            return
        }

        await withCheckedContinuation { continuation in
            waitersByQuery[query, default: []].append(continuation)
        }
    }

    func finish(query: String) {
        finishContinuations.removeValue(forKey: query)?.resume()
    }

    private func resumeWaiters(for query: String) {
        let continuations = waitersByQuery.removeValue(forKey: query) ?? []
        continuations.forEach { $0.resume() }
    }
}
