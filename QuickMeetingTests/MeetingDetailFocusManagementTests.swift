import Foundation
import Testing
@testable import QuickMeeting
#if canImport(AppKit)
import AppKit

struct MeetingDetailFocusManagementTests {
    @Test @MainActor
    func clearingMeetingDetailFocusRemovesCurrentFieldEditorResponder() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let containerView = NSView(frame: window.contentLayoutRect)
        let titleField = NSTextField(string: "Weekly Sync")
        titleField.frame = NSRect(x: 20, y: 20, width: 240, height: 24)
        containerView.addSubview(titleField)
        window.contentView = containerView

        window.makeKeyAndOrderFront(nil)
        #expect(window.makeFirstResponder(titleField))
        let fieldEditor = try #require(window.firstResponder)

        clearMeetingDetailFocus(in: window)

        #expect(window.firstResponder !== fieldEditor)
    }
}
#endif
