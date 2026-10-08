import SwiftUI
import ScreenSenseCore

public struct MenuBarView: View {
    @ObservedObject var coordinator: ScreenSenseCoordinator

    public init(coordinator: ScreenSenseCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ScreenSense")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Voice Screen Assistant (Phase 1)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                statusBadge
            }
            .padding(.bottom, 2)

            Divider()

            // Live State & Action Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: stateIcon)
                        .foregroundColor(stateColor)
                        .font(.body)
                    Text(coordinator.state.statusDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }

                if !coordinator.currentTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcript:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\"\(coordinator.currentTranscript)\"")
                            .font(.caption)
                            .italic()
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(6)
                    }
                }

                if !coordinator.lastExecutionMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: coordinator.state.statusDescription.contains("Error") ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(coordinator.state.statusDescription.contains("Error") ? .red : .green)
                        Text(coordinator.lastExecutionMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)

            // Global Shortcut Information
            HStack {
                Text("Global Shortcut:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("⌥ ⇧ Space")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)
            }

            Divider()

            // Permissions Checklist
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("System Permissions")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Refresh") {
                        coordinator.refreshPermissions()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                }

                permissionRow(
                    name: "Microphone",
                    granted: coordinator.permissionStatus.microphoneGranted,
                    target: .microphone
                )

                permissionRow(
                    name: "Speech Recognition",
                    granted: coordinator.permissionStatus.speechRecognitionGranted,
                    target: .speechRecognition
                )

                permissionRow(
                    name: "Accessibility (for ⌘V)",
                    granted: coordinator.permissionStatus.accessibilityGranted,
                    target: .accessibility
                )

                if !coordinator.permissionStatus.allGranted {
                    Button(action: {
                        Task {
                            await coordinator.requestAllPermissions()
                        }
                    }) {
                        Label("Request All Permissions", systemImage: "hand.raised.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }

            Divider()

            // Quick Actions & Testing
            HStack(spacing: 8) {
                Button(action: {
                    coordinator.handleHotkeyTriggered()
                }) {
                    Label(coordinator.state.isListening ? "Stop" : "Listen", systemImage: coordinator.state.isListening ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: {
                    coordinator.processTranscript("paste")
                }) {
                    Label("Test Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.red)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(badgeText)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(stateColor.opacity(0.12))
        .cornerRadius(12)
    }

    private var badgeText: String {
        switch coordinator.state {
        case .idle:
            return "IDLE"
        case .listening:
            return "LISTENING"
        case .processing:
            return "PROCESSING"
        case .executed:
            return "DONE"
        case .failed:
            return "ALERT"
        }
    }

    private var stateIcon: String {
        switch coordinator.state {
        case .idle:
            return "mic.circle"
        case .listening:
            return "waveform.circle.fill"
        case .processing:
            return "gearshape.arrow.triangle.2.circlepath"
        case .executed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var stateColor: Color {
        switch coordinator.state {
        case .idle:
            return .blue
        case .listening:
            return .red
        case .processing:
            return .orange
        case .executed:
            return .green
        case .failed:
            return .red
        }
    }

    @ViewBuilder
    private func permissionRow(name: String, granted: Bool, target: SystemSettingsTarget) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
                .font(.caption)

            Text(name)
                .font(.caption)

            Spacer()

            if !granted {
                Button("Open Settings") {
                    coordinator.openSettings(for: target)
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .foregroundColor(.accentColor)
            }
        }
    }
}
