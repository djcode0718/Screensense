import Foundation
import CoreGraphics
import ApplicationServices

public enum InputSimulationError: LocalizedError, Sendable {
    case accessibilityPermissionRequired
    case eventCreationFailed
    case postFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "ScreenSense requires Accessibility permission to simulate keystrokes (⌘V). Please grant Accessibility permission in System Settings -> Privacy & Security -> Accessibility."
        case .eventCreationFailed:
            return "Failed to create CGEvent for keyboard simulation."
        case .postFailed:
            return "Failed to dispatch keyboard event to the active application."
        }
    }
}

/// Native macOS CGEvent-based input simulator
public final class CGEventInputSimulator: InputSimulatorProtocol, @unchecked Sendable {
    // Virtual keycode for ANSI 'V'
    private let kVK_ANSI_V: CGKeyCode = 0x09

    public init() {}

    public func simulatePasteShortcut() throws {
        // Verify accessibility trust
        guard AXIsProcessTrusted() else {
            ScreenSenseLogger.input.error("Accessibility permission missing when attempting to post ⌘V")
            throw InputSimulationError.accessibilityPermissionRequired
        }

        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: false) else {
            ScreenSenseLogger.input.error("Failed to instantiate CGEvent key pair")
            throw InputSimulationError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        ScreenSenseLogger.input.info("Simulating ⌘V key press...")

        keyDown.post(tap: .cghidEventTap)
        // Brief microsecond pause between down and up for OS dispatch reliability
        usleep(15_000)
        keyUp.post(tap: .cghidEventTap)

        ScreenSenseLogger.input.info("⌘V key press simulated successfully")
    }
}
