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

    @Test
    func startDiarizationTrackingRegistersZeroProgress() {
        let meetingID = UUID()

        let center = TranscriptionProgressCenter()
        center.startDiarizationTracking(meetingID: meetingID)

        #expect(center.diarizationProgress(for: meetingID) == 0)
    }

    @Test
    func updateDiarizationProgressClampsAndIgnoresRegressions() {
        let meetingID = UUID()

        let center = TranscriptionProgressCenter()
        center.startDiarizationTracking(meetingID: meetingID)
        center.updateDiarizationProgress(0.5, for: meetingID)
        center.updateDiarizationProgress(1.8, for: meetingID)
        center.updateDiarizationProgress(0.2, for: meetingID)

        #expect(center.diarizationProgress(for: meetingID) == 1)
    }

    @Test
    func finishTrackingClearsDiarizationProgress() {
        let meetingID = UUID()

        let center = TranscriptionProgressCenter()
        center.startTracking(meetingID: meetingID)
        center.startDiarizationTracking(meetingID: meetingID)
        center.finishTracking(meetingID: meetingID)

        #expect(center.progress(for: meetingID) == nil)
        #expect(center.diarizationProgress(for: meetingID) == nil)
    }
}
