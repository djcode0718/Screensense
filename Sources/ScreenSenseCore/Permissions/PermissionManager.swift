import Foundation
import AVFoundation
import Speech
import ApplicationServices
import AppKit

public final class PermissionManager: PermissionManagerProtocol, @unchecked Sendable {
    public init() {}

    public func checkAllPermissions() -> PermissionStatus {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let execPath = Bundle.main.executablePath ?? "unknown"
        let bundlePath = Bundle.main.bundlePath

        ScreenSenseLogger.permissions.info("=== Permission Check Starting ===")
        ScreenSenseLogger.permissions.info("Process Info: BundleID=\(bundleID, privacy: .public), ExecPath=\(execPath, privacy: .public), BundlePath=\(bundlePath, privacy: .public)")

        let micGranted = checkMicrophone()
        let speechGranted = checkSpeechRecognition()
        let axGranted = checkAccessibility()
        let screenGranted = checkScreenRecording()

        ScreenSenseLogger.permissions.info("=== Permission Check Results: Mic=\(micGranted), Speech=\(speechGranted), AX=\(axGranted), Screen=\(screenGranted) ===")

        return PermissionStatus(
            microphoneGranted: micGranted,
            speechRecognitionGranted: speechGranted,
            accessibilityGranted: axGranted,
            screenRecordingGranted: screenGranted
        )
    }

    public func checkMicrophone() -> Bool {
        if #available(macOS 14.0, *) {
            let recordPerm = AVAudioApplication.shared.recordPermission
            let recordPermString: String
            switch recordPerm {
            case .undetermined: recordPermString = "undetermined (1970168948)"
            case .denied: recordPermString = "denied (1684369017)"
            case .granted: recordPermString = "granted (1735552628)"
            @unknown default: recordPermString = "unknown (\(recordPerm.rawValue))"
            }
            let isGranted = (recordPerm == .granted)
            ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Microphone: API='AVAudioApplication.shared.recordPermission', rawValue=\(recordPermString, privacy: .public), finalBool=\(isGranted)")
            return isGranted
        } else {
            let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            let statusString: String
            switch authStatus {
            case .notDetermined: statusString = "notDetermined (0)"
            case .restricted: statusString = "restricted (1)"
            case .denied: statusString = "denied (2)"
            case .authorized: statusString = "authorized (3)"
            @unknown default: statusString = "unknown (\(authStatus.rawValue))"
            }
            let isGranted = (authStatus == .authorized)
            ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Microphone: API='AVCaptureDevice.authorizationStatus(for: .audio)', rawValue=\(statusString, privacy: .public), finalBool=\(isGranted)")
            return isGranted
        }
    }

    public func requestMicrophonePermission() async -> Bool {
        ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Requesting microphone permission...")
        if #available(macOS 14.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Microphone request result: \(granted)")
            return granted
        } else {
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Microphone request result: \(granted)")
            return granted
        }
    }

    public func checkSpeechRecognition() -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        let statusString: String
        switch status {
        case .notDetermined: statusString = "notDetermined (0)"
        case .denied: statusString = "denied (1)"
        case .restricted: statusString = "restricted (2)"
        case .authorized: statusString = "authorized (3)"
        @unknown default: statusString = "unknown (\(status.rawValue))"
        }
        let isGranted = (status == .authorized)
        ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Speech Recognition: API='SFSpeechRecognizer.authorizationStatus()', rawValue=\(statusString, privacy: .public), finalBool=\(isGranted)")
        return isGranted
    }

    public func requestSpeechRecognitionPermission() async -> Bool {
        ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Requesting speech recognition permission...")
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let granted = (status == .authorized)
        ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Speech recognition request result: \(granted) (status=\(status.rawValue))")
        return granted
    }

    public func checkAccessibility() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let optionsFalse = [promptKey: false] as CFDictionary
        let rawWithOptions = AXIsProcessTrustedWithOptions(optionsFalse)
        let rawClassic = AXIsProcessTrusted()

        ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Accessibility: API='AXIsProcessTrustedWithOptions([prompt:false])' returned=\(rawWithOptions), API='AXIsProcessTrusted()' returned=\(rawClassic), finalBool=\(rawWithOptions)")
        return rawWithOptions
    }

    public func requestAccessibilityPermission() -> Bool {
        ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Checking/prompting accessibility permission via AXIsProcessTrustedWithOptions([prompt:true])...")
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Accessibility prompt result: isTrusted=\(isTrusted)")
        return isTrusted
    }

    public func checkScreenRecording() -> Bool {
        let rawPreflight = CGPreflightScreenCaptureAccess()
        ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Screen Recording: API='CGPreflightScreenCaptureAccess()' returned=\(rawPreflight), finalBool=\(rawPreflight)")
        return rawPreflight
    }

    public func requestScreenRecordingPermission() -> Bool {
        ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Requesting screen recording permission via CGRequestScreenCaptureAccess()...")
        let granted = CGRequestScreenCaptureAccess()
        ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Screen recording request result: \(granted)")
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

        ScreenSenseLogger.permissions.info("[DIAGNOSTIC] Opening System Settings URL: \(urlString, privacy: .public)")
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
