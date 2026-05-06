import Foundation
import Testing
@testable import QuickMeeting

@MainActor
struct TranscriptionProgressCenterTests {
    @Test
    func startTrackingRegistersZeroProgress() {
        let meetingID = UUID()

        let center = TranscriptionProgressCenter()
        center.startTracking(meetingID: meetingID)

        #expect(center.progress(for: meetingID) == 0)
    }

    @Test
    func updateProgressClampsValuesAndIgnoresRegressions() {
        let meetingID = UUID()

        let center = TranscriptionProgressCenter()
        center.startTracking(meetingID: meetingID)
        center.updateProgress(0.42, for: meetingID)
        center.updateProgress(1.4, for: meetingID)
        center.updateProgress(0.31, for: meetingID)

        #expect(center.progress(for: meetingID) == 1)
    }

    @Test
    func finishTrackingRemovesProgressEntry() {
        let meetingID = UUID()

        let center = TranscriptionProgressCenter()
        center.startTracking(meetingID: meetingID)
        center.finishTracking(meetingID: meetingID)

        #expect(center.progress(for: meetingID) == nil)
    }
}
