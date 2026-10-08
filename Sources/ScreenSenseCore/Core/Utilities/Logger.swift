import Foundation
import os

/// Structured logger for ScreenSense subsystems
public enum ScreenSenseLogger {
    private static let subsystem = "com.screensense.app"

    public static let app = Logger(subsystem: subsystem, category: "App")
    public static let hotkey = Logger(subsystem: subsystem, category: "Hotkey")
    public static let voice = Logger(subsystem: subsystem, category: "Voice")
    public static let recognition = Logger(subsystem: subsystem, category: "SpeechRecognition")
    public static let parser = Logger(subsystem: subsystem, category: "CommandParser")
    public static let input = Logger(subsystem: subsystem, category: "InputSimulation")
    public static let permissions = Logger(subsystem: subsystem, category: "Permissions")
}
