//
//  RecordingPermissions.swift
//  QuickMeeting
//
//  Created by Codex on 04.05.2026.
//

import AVFAudio
import CoreGraphics
import Foundation

enum RecordingPermissionResult: Equatable {
    case granted
    case denied(message: String)
}

protocol RecordingPermissions {
    func ensurePermissions() async -> RecordingPermissionResult
}

struct NativeRecordingPermissions: RecordingPermissions {
    func ensurePermissions() async -> RecordingPermissionResult {
        guard ensureScreenRecordingPermission() else {
            return .denied(message: "Screen recording permission is required.")
        }

        guard await ensureMicrophonePermission() else {
            return .denied(message: "Microphone permission is required.")
        }

        return .granted
    }

    private func ensureScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
