import Foundation
import AVFoundation
import Speech
import ApplicationServices
import AppKit

public final class PermissionManager: PermissionManagerProtocol, @unchecked Sendable {
    public init() {}

    public func checkAllPermissions() -> PermissionStatus {
        let micGranted = checkMicrophone()
        let speechGranted = checkSpeechRecognition()
        let axGranted = checkAccessibility()
        let screenGranted = checkScreenRecording()

        return PermissionStatus(
            microphoneGranted: micGranted,
            speechRecognitionGranted: speechGranted,
            accessibilityGranted: axGranted,
            screenRecordingGranted: screenGranted
        )
    }

    public func checkMicrophone() -> Bool {
        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        } else {
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    public func requestMicrophonePermission() async -> Bool {
        ScreenSenseLogger.permissions.info("Requesting microphone permission...")
        if #available(macOS 14.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            ScreenSenseLogger.permissions.info("Microphone permission result: \(granted)")
            return granted
        } else {
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            ScreenSenseLogger.permissions.info("Microphone permission result: \(granted)")
            return granted
        }
    }

    public func checkSpeechRecognition() -> Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    public func requestSpeechRecognitionPermission() async -> Bool {
        ScreenSenseLogger.permissions.info("Requesting speech recognition permission...")
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let granted = (status == .authorized)
        ScreenSenseLogger.permissions.info("Speech recognition permission result: \(granted)")
        return granted
    }

    public func checkAccessibility() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func requestAccessibilityPermission() -> Bool {
        ScreenSenseLogger.permissions.info("Checking/prompting accessibility permission...")
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        ScreenSenseLogger.permissions.info("Accessibility trusted: \(isTrusted)")
        return isTrusted
    }

    public func checkScreenRecording() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    public func requestScreenRecordingPermission() -> Bool {
        ScreenSenseLogger.permissions.info("Requesting screen recording permission...")
        let granted = CGRequestScreenCaptureAccess()
        ScreenSenseLogger.permissions.info("Screen recording granted: \(granted)")
        return granted
    }

    public func openSystemSettings(for target: SystemSettingsTarget) {
        let urlString: String
        switch target {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
