//
//  NativeMicrophoneActivitySource.swift
//  QuickMeeting
//
//  Created by Codex on 14.05.2026.
//

import CoreAudio
import Foundation

protocol AudioInputDeviceInventory: Sendable {
    func inputDevices() throws -> [any AudioInputDevice]
}

protocol AudioInputDevice: Sendable {
    var id: String { get }
    func isRunningSomewhere() throws -> Bool
}

final class NativeMicrophoneActivitySource: MicrophoneActivitySource, @unchecked Sendable {
    private let deviceInventory: any AudioInputDeviceInventory

    init(deviceInventory: any AudioInputDeviceInventory = CoreAudioInputDeviceInventory()) {
        self.deviceInventory = deviceInventory
    }

    func isMicrophoneActive() -> Bool {
        do {
            return try deviceInventory.inputDevices().contains { device in
                try device.isRunningSomewhere()
            }
        } catch {
            return false
        }
    }
}

private struct CoreAudioInputDeviceInventory: AudioInputDeviceInventory {
    func inputDevices() throws -> [any AudioInputDevice] {
        try deviceIDs().compactMap { deviceID in
            let device = CoreAudioInputDevice(deviceID: deviceID)
            return try device.supportsInput() ? device : nil
        }
    }

    private func deviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr else {
            throw CoreAudioInputDeviceError.propertyReadFailed(status: sizeStatus)
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)
        let readStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard readStatus == noErr else {
            throw CoreAudioInputDeviceError.propertyReadFailed(status: readStatus)
        }

        return deviceIDs
    }
}

private struct CoreAudioInputDevice: AudioInputDevice {
    let deviceID: AudioDeviceID

    var id: String {
        String(deviceID)
    }

    func isRunningSomewhere() throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr else {
            throw CoreAudioInputDeviceError.propertyReadFailed(status: status)
        }

        return value != 0
    }

    func supportsInput() throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        let sizeStatus = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr else {
            throw CoreAudioInputDeviceError.propertyReadFailed(status: sizeStatus)
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPointer.deallocate() }

        let readStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            rawPointer
        )
        guard readStatus == noErr else {
            throw CoreAudioInputDeviceError.propertyReadFailed(status: readStatus)
        }

        let audioBufferList = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let bufferCount = Int(audioBufferList.pointee.mNumberBuffers)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

        guard bufferCount == buffers.count else {
            return !buffers.isEmpty
        }

        return buffers.contains { $0.mNumberChannels > 0 }
    }
}

private enum CoreAudioInputDeviceError: Error {
    case propertyReadFailed(status: OSStatus)
}

