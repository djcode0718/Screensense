import SwiftUI
import AppKit
import ScreenSenseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory / menu bar app (no dock icon clutter)
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct ScreenSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = ScreenSenseCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(coordinator: coordinator)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuBarIcon)
                if coordinator.state.isListening {
                    Text("Listening...")
                        .font(.caption2)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        // Coordinator will start when created
        // We defer register to after app launches
        DispatchQueue.main.async { [self] in
            coordinator.start()
        }
    }

    private var menuBarIcon: String {
        switch coordinator.state {
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
