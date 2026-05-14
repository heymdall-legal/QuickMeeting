import Foundation
import Testing
@testable import QuickMeeting

struct NativeMeetingAppActivitySourceTests {
    @Test
    func keepsRecentFocusTrueForThirtySecondsAfterFrontmostLoss() {
        let frontmost = MutableValue<String?>("kontur.talk")
        let visibleWindows = MutableValue<Set<String>>([])
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 100))
        let microphone = StubMicrophoneActivitySource(isActive: true)
        let source = NativeMeetingAppActivitySource(
            runningBundleIdentifiers: { ["kontur.talk"] },
            frontmostBundleIdentifier: { frontmost.value },
            visibleWindowBundleIdentifiers: { visibleWindows.value },
            microphoneActivitySource: microphone,
            now: { clock.now },
            recentFocusWindow: 30
        )

        _ = source.sample(for: .tolk)
        frontmost.value = nil
        clock.now = Date(timeIntervalSinceReferenceDate: 125)

        let sample = source.sample(for: .tolk)
        #expect(sample.hadRecentFocus == true)
        #expect(sample.hasVisibleWindow == false)
        #expect(sample.isMicrophoneActive == true)
    }

    @Test
    func expiresRecentFocusAfterThirtySeconds() {
        let frontmost = MutableValue<String?>("kontur.talk")
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 100))
        let source = NativeMeetingAppActivitySource(
            runningBundleIdentifiers: { ["kontur.talk"] },
            frontmostBundleIdentifier: { frontmost.value },
            visibleWindowBundleIdentifiers: { [] },
            microphoneActivitySource: StubMicrophoneActivitySource(isActive: true),
            now: { clock.now },
            recentFocusWindow: 30
        )

        _ = source.sample(for: .tolk)
        frontmost.value = nil
        clock.now = Date(timeIntervalSinceReferenceDate: 131)

        let sample = source.sample(for: .tolk)
        #expect(sample.hadRecentFocus == false)
    }

    @Test
    func returnsInactiveSignalsWhenMicrophoneIsOff() {
        let source = NativeMeetingAppActivitySource(
            runningBundleIdentifiers: { ["kontur.talk"] },
            frontmostBundleIdentifier: { "kontur.talk" },
            visibleWindowBundleIdentifiers: { ["kontur.talk"] },
            microphoneActivitySource: StubMicrophoneActivitySource(isActive: false),
            now: Date.init,
            recentFocusWindow: 30
        )

        let sample = source.sample(for: .tolk)
        #expect(sample.isRunning == true)
        #expect(sample.hasVisibleWindow == true)
        #expect(sample.isMicrophoneActive == false)
    }
}

private final class MutableValue<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private final class StubMicrophoneActivitySource: MicrophoneActivitySource, @unchecked Sendable {
    var isActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
    }

    func isMicrophoneActive() -> Bool {
        isActive
    }
}

private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
