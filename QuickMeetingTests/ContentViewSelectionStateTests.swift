import Foundation
import Testing
@testable import QuickMeeting

struct ContentViewSelectionStateTests {
    @Test
    func defaultSelectionIsHome() {
        #expect(defaultSidebarSelection() == .home)
    }

    @Test
    func selectedMeetingRemainsWhenItStillExists() {
        let meetingID = UUID()

        let selection = reconciledSidebarSelection(
            currentSelection: .meeting(meetingID),
            availableMeetingIDs: [meetingID]
        )

        #expect(selection == .meeting(meetingID))
    }

    @Test
    func missingSelectedMeetingFallsBackToHome() {
        let selection = reconciledSidebarSelection(
            currentSelection: .meeting(UUID()),
            availableMeetingIDs: []
        )

        #expect(selection == .home)
    }

    @Test
    func nonMeetingSelectionIsUnaffectedByMeetingChanges() {
        let selection = reconciledSidebarSelection(
            currentSelection: .settings,
            availableMeetingIDs: []
        )

        #expect(selection == .settings)
    }
}
