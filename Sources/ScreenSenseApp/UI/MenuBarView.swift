import SwiftUI
import ScreenSenseCore
import AppKit

public struct MenuBarView: View {
    @ObservedObject var coordinator: ScreenSenseCoordinator
    @State private var selectedTab: Int = 0
    @State private var isCapturingContext = false
    @State private var contextMessage: String = ""

    public init(coordinator: ScreenSenseCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ScreenSense")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Voice & Screen Context Assistant")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                statusBadge
            }

            // Tab Selector (Controls vs Debug Context View)
            Picker("", selection: $selectedTab) {
                Text("Voice & Controls").tag(0)
                Text("Screen Context (Debug)").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedTab == 0 {
                voiceAndControlsView
            } else {
                contextDebugView
            }

            Divider()

            // Footer / Quit
            HStack {
                Text("⌥ ⇧ Space")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)

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
        .frame(width: 380)
    }

    // MARK: - Voice & Controls View (Phase 1)
    private var voiceAndControlsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Live State Card
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: stateIcon)
                        .foregroundColor(stateColor)
                    Text(coordinator.state.statusDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }

                // Active App, Active Tab & Context Status
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Active App:").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                        Text(coordinator.currentApplicationName)
                            .font(.caption2)
                            .fontWeight(.medium)
                        Spacer()
                        Circle()
                            .fill(coordinator.unifiedContextManager.isBridgeConnected ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(coordinator.unifiedContextManager.isBridgeConnected ? "Bridge Connected" : "Bridge Idle")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Active Tab:").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                        Text(coordinator.activeTabTitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    HStack(alignment: .top) {
                        Text("Context:").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                        Text(coordinator.contextStatusDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        Spacer()
                    }
                    if let fallback = coordinator.unifiedContextManager.fallbackReason {
                        HStack(alignment: .top) {
                            Text("Fallback Reason:").font(.system(size: 9)).fontWeight(.bold).foregroundColor(.orange)
                            Text(fallback)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            Spacer()
                        }
                    }
                }
                .padding(6)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)

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

            // Permissions Checklist
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Permissions Checklist")
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

                permissionRow(name: "Microphone", granted: coordinator.permissionStatus.microphoneGranted, target: .microphone)
                permissionRow(name: "Speech Recognition", granted: coordinator.permissionStatus.speechRecognitionGranted, target: .speechRecognition)
                permissionRow(name: "Accessibility (⌘V)", granted: coordinator.permissionStatus.accessibilityGranted, target: .accessibility)
                permissionRow(name: "Screen Recording", granted: coordinator.permissionStatus.screenRecordingGranted, target: .screenRecording)

                if !coordinator.permissionStatus.allGranted {
                    Button(action: {
                        Task { await coordinator.requestAllPermissions() }
                    }) {
                        Label("Request Permissions", systemImage: "hand.raised.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // Quick Actions
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
            }
        }
    }

    // MARK: - Screen Context Debug View (Phase 2)
    private var contextDebugView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Context Action Triggers
            HStack(spacing: 6) {
                Button("Capture Screen") {
                    Task {
                        isCapturingContext = true
                        do {
                            _ = try await coordinator.captureScreenOnly()
                            contextMessage = "Screen captured successfully"
                        } catch {
                            contextMessage = "Screen capture failed: \(error.localizedDescription)"
                        }
                        isCapturingContext = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Fetch DOM") {
                    Task {
                        isCapturingContext = true
                        let dom = await coordinator.fetchDOMContextOnly()
                        if dom != nil {
                            contextMessage = "DOM context received (\(dom!.elements.count) elements)"
                        } else {
                            contextMessage = "No DOM received. Open Chrome with extension."
                        }
                        isCapturingContext = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Fusion") {
                    Task {
                        isCapturingContext = true
                        do {
                            let unified = try await coordinator.captureUnifiedContext()
                            contextMessage = "Unified context: \(unified.elements.count) elements, source: \(unified.source.rawValue)"
                        } catch {
                            contextMessage = "Fusion error: \(error.localizedDescription)"
                        }
                        isCapturingContext = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if !contextMessage.isEmpty {
                Text(contextMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let ctx = coordinator.latestContext {
                VStack(alignment: .leading, spacing: 6) {
                    // Context Metadata Box
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Source:").fontWeight(.bold)
                            Text(ctx.source.rawValue.uppercased())
                                .foregroundColor(.accentColor)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(ctx.elements.count) elements").font(.caption2).foregroundColor(.secondary)
                        }
                        .font(.caption)

                        HStack {
                            Text("Viewport:").fontWeight(.bold)
                            Text("\(Int(ctx.viewport.width)) × \(Int(ctx.viewport.height)) (scroll: \(Int(ctx.viewport.scrollY))px)")
                        }
                        .font(.caption2)

                        if let title = ctx.viewport.pageTitle {
                            Text("Title: \(title)")
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)

                    // Screenshot Thumbnail if available
                    if let screenshot = ctx.screenshot, let base64 = screenshot.pngBase64, let data = Data(base64Encoded: base64), let nsImage = NSImage(data: data) {
                        HStack {
                            Text("Visual Confirmation:")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Spacer()
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 50)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.2), lineWidth: 1))
                        }
                    }

                    // Elements List
                    Text("VISIBLE ELEMENTS (READING ORDER):")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)

                    if ctx.elements.isEmpty {
                        Text("No DOM text elements visible in current viewport (or non-browser context).")
                            .font(.caption2)
                            .italic()
                            .foregroundColor(.secondary)
                            .padding(6)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(ctx.spatiallySortedElements.prefix(15).enumerated()), id: \.offset) { index, el in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text("[\(index + 1)] \(el.type.rawValue)")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.accentColor)

                                            Spacer()

                                            Text("\(Int(el.visibilityPercentage * 100))% visible")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.green)
                                        }

                                        Text("\"\(el.text)\"")
                                            .font(.caption)
                                            .lineLimit(2)

                                        Text("bounds: x:\(Int(el.bounds.x)) y:\(Int(el.bounds.y)) w:\(Int(el.bounds.width)) h:\(Int(el.bounds.height))")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(6)
                                    .background(Color.primary.opacity(0.03))
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Screen Context Captured Yet")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Click 'Capture Screen', 'Fetch DOM', or 'Fusion' to inspect.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(8)
            }
        }
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
        case .idle: return coordinator.permissionStatus.allGranted ? "READY" : "IDLE"
        case .listening: return "LISTENING"
        case .processing: return "PROCESSING"
        case .executed: return "DONE"
        case .failed: return "ALERT"
        }
    }

    private var stateIcon: String {
        switch coordinator.state {
        case .idle: return coordinator.permissionStatus.allGranted ? "checkmark.circle" : "mic.circle"
        case .listening: return "waveform.circle.fill"
        case .processing: return "gearshape.arrow.triangle.2.circlepath"
        case .executed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var stateColor: Color {
        switch coordinator.state {
        case .idle: return coordinator.permissionStatus.allGranted ? .green : .blue
        case .listening: return .red
        case .processing: return .orange
        case .executed: return .green
        case .failed: return .red
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
                Button("Settings") {
                    coordinator.openSettings(for: target)
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .foregroundColor(.accentColor)
            }
        }
    }
}
