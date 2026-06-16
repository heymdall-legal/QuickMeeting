import Combine
import Foundation

@MainActor
final class SidebarMeetingSearchController: ObservableObject {
    @Published private(set) var matchingMeetingIDs = Set<UUID>()

    private let search: @Sendable ([MeetingSearchDocument], String) async -> Set<UUID>
    private var documents = [MeetingSearchDocument]()
    private var currentQuery = ""
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0

    init(
        search: @escaping @Sendable ([MeetingSearchDocument], String) async -> Set<UUID> = { documents, query in
            searchMeetingIDs(in: documents, query: query)
        }
    ) {
        self.search = search
    }

    deinit {
        searchTask?.cancel()
    }

    func replaceMeetings(_ meetings: [Meeting]) {
        documents = meetings.map(meetingSearchDocument)
        scheduleSearch()
    }

    func updateQuery(_ query: String) {
        currentQuery = query
        scheduleSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchGeneration += 1

        let normalizedQuery = normalizedMeetingSearchQuery(currentQuery)
        guard !normalizedQuery.isEmpty else {
            matchingMeetingIDs = Set(documents.map(\.id))
            return
        }

        let documents = documents
        let query = currentQuery
        let search = search
        let generation = searchGeneration

        searchTask = Task { [weak self] in
            let matchingMeetingIDs = await Task.detached(priority: .userInitiated) {
                await search(documents, query)
            }.value

            guard !Task.isCancelled else {
                return
            }

            guard let self, generation == self.searchGeneration else {
                return
            }

            self.matchingMeetingIDs = matchingMeetingIDs
        }
    }
}
