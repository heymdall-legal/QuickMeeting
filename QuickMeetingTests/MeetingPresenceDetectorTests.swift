import Foundation
import Testing
@testable import QuickMeeting

struct MeetingPresenceDetectorTests {
    @Test
    func inactiveWhenMicrophoneIsOffEvenIfAppSignalsMatch() {
        var detector = MeetingPresenceDetector(requiredStableSampleCount: 3)
        let sample = MeetingAppActivitySample(
            bundleIdentifier: "kontur.talk",
            isRunning: true,
            isFrontmost: true,
            hadRecentFocus: true,
            hasVisibleWindow: true,
            isMicrophoneActive: false
        )

        #expect(detector.evaluate(sample) == .inactive)
        #expect(detector.evaluate(sample) == .inactive)
    }

    @Test
    func promotesCandidateToActiveWhenMicrophoneAndAppEvidenceStayStable() {
        var detector = MeetingPresenceDetector(requiredStableSampleCount: 3)
        let sample = MeetingAppActivitySample(
            bundleIdentifier: "kontur.talk",
            isRunning: true,
            isFrontmost: false,
            hadRecentFocus: true,
            hasVisibleWindow: false,
            isMicrophoneActive: true
        )

        #expect(detector.evaluate(sample) == .candidateActive)
        #expect(detector.evaluate(sample) == .candidateActive)
        #expect(detector.evaluate(sample) == .activeMeeting)
    }

    @Test
    func resetsToInactiveWhenMicrophoneDrops() {
        var detector = MeetingPresenceDetector(requiredStableSampleCount: 2)
        let activeSample = MeetingAppActivitySample(
            bundleIdentifier: "kontur.talk",
            isRunning: true,
            isFrontmost: true,
            hadRecentFocus: true,
            hasVisibleWindow: true,
            isMicrophoneActive: true
        )
        let inactiveSample = MeetingAppActivitySample(
            bundleIdentifier: "kontur.talk",
            isRunning: true,
            isFrontmost: true,
            hadRecentFocus: true,
            hasVisibleWindow: true,
            isMicrophoneActive: false
        )

        #expect(detector.evaluate(activeSample) == .candidateActive)
        #expect(detector.evaluate(activeSample) == .activeMeeting)
        #expect(detector.evaluate(inactiveSample) == .inactive)
        #expect(detector.evaluate(activeSample) == .candidateActive)
    }
}
