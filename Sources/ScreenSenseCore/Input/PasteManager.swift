import Foundation

/// High-level paste coordinator that executes standard macOS paste (⌘V)
public final class PasteManager: PasteManagerProtocol, Sendable {
    private let inputSimulator: InputSimulatorProtocol

    public init(inputSimulator: InputSimulatorProtocol = CGEventInputSimulator()) {
        self.inputSimulator = inputSimulator
    }

    public func executePaste() throws {
        ScreenSenseLogger.input.info("Executing paste command...")
        try inputSimulator.simulatePasteShortcut()
    }
}
