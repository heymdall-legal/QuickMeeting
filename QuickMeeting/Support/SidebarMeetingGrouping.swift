import Foundation

struct SidebarMeetingGroup {
    let title: String
    let meetings: [Meeting]
}

func groupSidebarMeetings(
    _ meetings: [Meeting],
    now: Date = Date(),
    calendar: Calendar = .current,
    dateFormatter: DateFormatter = makeSidebarMeetingGroupDateFormatter()
) -> [SidebarMeetingGroup] {
    var groupsByDay = [Date: [Meeting]]()

    for meeting in meetings {
        let day = calendar.startOfDay(for: meeting.startedAt)
        groupsByDay[day, default: []].append(meeting)
    }

    return groupsByDay.keys
        .sorted(by: >)
        .map { day in
            SidebarMeetingGroup(
                title: sidebarMeetingGroupTitle(
                    for: day,
                    now: now,
                    calendar: calendar,
                    dateFormatter: dateFormatter
                ),
                meetings: groupsByDay[day] ?? []
            )
        }
}

private func sidebarMeetingGroupTitle(
    for day: Date,
    now: Date,
    calendar: Calendar,
    dateFormatter: DateFormatter
) -> String {
    if calendar.isDate(day, inSameDayAs: now) {
        return "Today"
    }

    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
       calendar.isDate(day, inSameDayAs: yesterday) {
        return "Yesterday"
    }

    return dateFormatter.string(from: day)
}

private func makeSidebarMeetingGroupDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .none
    return formatter
}
