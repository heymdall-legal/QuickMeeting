import Foundation
import Testing
@testable import QuickMeeting

struct MeetingPresenceDetectorTests {
    @Test
    func promotesCandidateToActiveAfterStableSamples() {
        var detector = MeetingPresenceDetector(requiredStableSampleCount: 3)
        let sample = MeetingAppActivitySample(
            bundleIdentifier: "ru.tolk.desktop",
            isRunning: true,
            isFrontmost: true,
            hadRecentFocus: true,
            hasVisibleWindow: true,
            isUsingMedia: true
        )

        #expect(detector.evaluate(sample) == .candidateActive)
        #expect(detector.evaluate(sample) == .candidateActive)
        #expect(detector.evaluate(sample) == .activeMeeting)
    }
}
