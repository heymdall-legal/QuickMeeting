import Foundation
import Testing
@testable import QuickMeeting

struct SidebarMeetingGroupingTests {
    @Test
    func groupsMeetingsByDayWithTodayYesterdayAndSystemDateTitles() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = Date(timeIntervalSince1970: 1_781_436_000) // 2026-06-16 12:00:00 UTC
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = .none

        let todayMeeting = makeMeeting(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            startedAt: Date(timeIntervalSince1970: 1_781_428_800) // 2026-06-16 10:00:00 UTC
        )
        let yesterdayMeeting = makeMeeting(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            startedAt: Date(timeIntervalSince1970: 1_781_338_800) // 2026-06-15 09:00:00 UTC
        )
        let olderMeeting = makeMeeting(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            startedAt: Date(timeIntervalSince1970: 1_781_161_200) // 2026-06-13 07:40:00 UTC
        )
        let anotherOlderMeetingSameDay = makeMeeting(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            startedAt: Date(timeIntervalSince1970: 1_781_168_400) // 2026-06-13 09:40:00 UTC
        )

        let groups = groupSidebarMeetings(
            [olderMeeting, yesterdayMeeting, todayMeeting, anotherOlderMeetingSameDay],
            now: now,
            calendar: calendar,
            dateFormatter: formatter
        )

        #expect(groups.map(\.title) == ["Today", "Yesterday", "6/13/26"])
        #expect(groups[0].meetings.map(\.id) == [todayMeeting.id])
        #expect(groups[1].meetings.map(\.id) == [yesterdayMeeting.id])
        #expect(groups[2].meetings.map(\.id) == [olderMeeting.id, anotherOlderMeetingSameDay.id])
    }

    private func makeMeeting(id: UUID, startedAt: Date) -> Meeting {
        Meeting(
            id: id,
            title: "Meeting \(id.uuidString)",
            startedAt: startedAt,
            status: .completed,
            audioFilePath: "/tmp/audio.wav"
        )
    }
}
