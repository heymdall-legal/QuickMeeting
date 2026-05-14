import Foundation
import Testing
@testable import QuickMeeting

struct NativeMicrophoneActivitySourceTests {
    @Test
    func returnsTrueWhenAnyInputDeviceReportsRunning() {
        let source = NativeMicrophoneActivitySource(
            deviceInventory: StubAudioInputDeviceInventory(
                devices: [
                    StubAudioInputDevice(id: "built-in", isRunningSomewhere: false),
                    StubAudioInputDevice(id: "usb-mic", isRunningSomewhere: true)
                ]
            )
        )

        #expect(source.isMicrophoneActive() == true)
    }

    @Test
    func returnsFalseWhenEnumerationFails() {
        let source = NativeMicrophoneActivitySource(
            deviceInventory: FailingAudioInputDeviceInventory()
        )

        #expect(source.isMicrophoneActive() == false)
    }
}

private struct StubAudioInputDeviceInventory: AudioInputDeviceInventory {
    let devices: [StubAudioInputDevice]

    func inputDevices() throws -> [any AudioInputDevice] {
        devices
    }
}

private struct FailingAudioInputDeviceInventory: AudioInputDeviceInventory {
    func inputDevices() throws -> [any AudioInputDevice] {
        throw CocoaError(.fileReadUnknown)
    }
}

private struct StubAudioInputDevice: AudioInputDevice {
    let id: String
    let runningSomewhere: Bool

    init(id: String, isRunningSomewhere: Bool) {
        self.id = id
        self.runningSomewhere = isRunningSomewhere
    }

    func isRunningSomewhere() throws -> Bool {
        runningSomewhere
    }
}
