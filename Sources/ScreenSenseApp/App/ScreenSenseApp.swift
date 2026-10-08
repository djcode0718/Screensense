import SwiftUI
import AppKit
import ScreenSenseCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let coordinator = ScreenSenseCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ScreenSenseLogger.app.info("ScreenSense launched via AppDelegate. Starting coordinator...")
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}

@main
struct ScreenSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("ScreenSense", systemImage: menuBarIcon) {
            MenuBarView(coordinator: appDelegate.coordinator)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch appDelegate.coordinator.state {
        case .idle:
            return "waveform"
        case .listening:
            return "record.circle.fill"
        case .processing:
            return "gearshape.fill"
        case .executed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}
