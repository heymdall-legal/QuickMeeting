import Foundation
import Testing
@testable import QuickMeeting

struct RecordingStatusTextTests {
    @Test
    func idleStateUsesReadyText() {
        #expect(recordingStatusText(for: .idle) == "Ready")
    }

    @Test
    func startingStateUsesStartingText() {
        #expect(recordingStatusText(for: .starting) == "Starting recording...")
    }

    @Test
    func recordingStateUsesInProgressText() {
        #expect(recordingStatusText(for: .recording(meetingID: UUID())) == "Recording in progress")
    }

    @Test
    func stoppingStateUsesStoppingText() {
        #expect(recordingStatusText(for: .stopping(meetingID: UUID())) == "Stopping recording...")
    }

    @Test
    func failedStateUsesFailureMessage() {
        #expect(recordingStatusText(for: .failed(message: "Mic unavailable")) == "Mic unavailable")
    }
}
