import Foundation
import Testing
@testable import QuickMeeting
#if canImport(AppKit)
import AppKit

struct MeetingDetailFocusManagementTests {
    @Test
    func detailHeaderActionsShowTranscriptSpecificButtons() {
        let actions = meetingDetailHeaderActions(
            activeTab: .transcript,
            summaryState: .idle
        )

        #expect(actions.map(\.help) == ["Copy transcript", "Re-transcribe", "Delete"])
        #expect(actions.map(\.systemName) == ["doc.on.doc", "arrow.clockwise", "trash"])
    }

    @Test
    func detailHeaderActionsShowSummarySpecificButtons() {
        let actions = meetingDetailHeaderActions(
            activeTab: .summary,
            summaryState: .ready("Stored summary")
        )

        #expect(actions.map(\.help) == ["Copy summary", "Regenerate summary", "Delete"])
        #expect(actions.map(\.systemName) == ["doc.on.doc", "sparkles", "trash"])
    }

    @Test @MainActor
    func meetingSummaryPaneSupportsReadyState() {
        _ = MeetingSummaryPane(
            state: .ready("Stored summary")
        )
    }

    @Test
    func meetingSummaryMarkdownParsingRemovesMarkdownMarkersAndPreservesEmphasis() throws {
        let attributedString = try makeMeetingSummaryAttributedString(
            from: """
            # Weekly Sync

            - **Ship** the feature
            - *Review* metrics
            """
        )

        #expect(attributedString.string.contains("# Weekly Sync") == false)
        #expect(attributedString.string.contains("**Ship**") == false)
        #expect(attributedString.string.contains("*Review*") == false)
        #expect(attributedString.string.contains("\u{2022} Ship the feature"))

        let headingFont = try #require(attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(headingFont.pointSize > NSFont.preferredFont(forTextStyle: .body).pointSize)

        let fullText = attributedString.string as NSString
        let boldRange = try #require(fullText.range(of: "Ship").toOptional())
        let italicRange = try #require(fullText.range(of: "Review").toOptional())

        let boldFont = try #require(
            attributedString.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        )
        let italicFont = try #require(
            attributedString.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont
        )

        #expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(italicFont.fontDescriptor.symbolicTraits.contains(.italic))
    }

    @Test
    func meetingBubbleShellUsesTranscriptBubbleMetrics() {
        #expect(MeetingBubbleShellMetrics.transcript.cornerRadius == 16)
        #expect(MeetingBubbleShellMetrics.transcript.horizontalPadding == 18)
        #expect(MeetingBubbleShellMetrics.transcript.verticalPadding == 13)
    }

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

private extension NSRange {
    func toOptional() -> NSRange? {
        location == NSNotFound ? nil : self
    }
}
#endif
