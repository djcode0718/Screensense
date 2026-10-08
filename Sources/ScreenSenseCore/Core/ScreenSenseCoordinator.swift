import Foundation
import Combine

/// Main Orchestrator for ScreenSense Phase 1
@MainActor
public final class ScreenSenseCoordinator: ObservableObject {
    @Published public private(set) var state: ScreenSenseState = .idle
    @Published public private(set) var permissionStatus: PermissionStatus = PermissionStatus()
    @Published public private(set) var currentTranscript: String = ""
    @Published public private(set) var lastCommandDescription: String = ""
    @Published public private(set) var lastExecutionMessage: String = ""

    private let hotkeyManager: HotkeyManagerProtocol
    private let voiceManager: VoiceManagerProtocol
    private let commandParser: CommandParserProtocol
    private let pasteManager: PasteManagerProtocol
    private let clipboardManager: ClipboardManagerProtocol
    private let permissionManager: PermissionManagerProtocol
    private let audioFeedback: AudioFeedbackProtocol

    public init(
        hotkeyManager: HotkeyManagerProtocol = CarbonHotkeyManager(),
        voiceManager: VoiceManagerProtocol = VoiceManager(),
        commandParser: CommandParserProtocol = DeterministicCommandParser(),
        pasteManager: PasteManagerProtocol = PasteManager(),
        clipboardManager: ClipboardManagerProtocol = SystemClipboardManager(),
        permissionManager: PermissionManagerProtocol = PermissionManager(),
        audioFeedback: AudioFeedbackProtocol = SystemAudioFeedback()
    ) {
        self.hotkeyManager = hotkeyManager
        self.voiceManager = voiceManager
        self.commandParser = commandParser
        self.pasteManager = pasteManager
        self.clipboardManager = clipboardManager
        self.permissionManager = permissionManager
        self.audioFeedback = audioFeedback
    }

    public func start() {
        ScreenSenseLogger.app.info("Starting ScreenSense Coordinator...")
        refreshPermissions()
        registerGlobalHotkey()
    }

    public func stop() {
        hotkeyManager.unregister()
        voiceManager.stopListening()
        state = .idle
        ScreenSenseLogger.app.info("ScreenSense Coordinator stopped")
    }

    public func refreshPermissions() {
        self.permissionStatus = permissionManager.checkAllPermissions()
        ScreenSenseLogger.permissions.info("Permissions status: Mic=\(self.permissionStatus.microphoneGranted), Speech=\(self.permissionStatus.speechRecognitionGranted), AX=\(self.permissionStatus.accessibilityGranted)")
    }

    public func requestAllPermissions() async {
        _ = await permissionManager.requestMicrophonePermission()
        _ = await permissionManager.requestSpeechRecognitionPermission()
        _ = permissionManager.requestAccessibilityPermission()
        refreshPermissions()
    }

    public func openSettings(for target: SystemSettingsTarget) {
        permissionManager.openSystemSettings(for: target)
    }

    private func registerGlobalHotkey() {
        do {
            try hotkeyManager.register { [weak self] in
                Task { @MainActor in
                    self?.handleHotkeyTriggered()
                }
            }
        } catch {
            ScreenSenseLogger.hotkey.error("Failed to register hotkey: \(error.localizedDescription)")
            self.state = .failed(error: "Hotkey registration failed: \(error.localizedDescription)")
        }
    }

    public func handleHotkeyTriggered() {
        ScreenSenseLogger.app.info("Hotkey triggered. Current state: \(String(describing: self.state))")

        if voiceManager.isListening {
            voiceManager.stopListening()
            return
        }

        refreshPermissions()

        guard permissionStatus.microphoneGranted && permissionStatus.speechRecognitionGranted else {
            ScreenSenseLogger.permissions.error("Microphone or Speech Recognition permission missing")
            state = .failed(error: "Missing permissions: \(permissionStatus.missingPermissions.joined(separator: ", "))")
            audioFeedback.playSound(.failure)
            return
        }

        startListening()
    }

    public func startListening() {
        currentTranscript = ""
        state = .listening
        ScreenSenseLogger.voice.info("Voice listening session started")

        do {
            try voiceManager.startListening(
                onPartialTranscript: { [weak self] partial in
                    Task { @MainActor in
                        self?.currentTranscript = partial
                        self?.state = .listening
                    }
                },
                onCompletion: { [weak self] result in
                    Task { @MainActor in
                        self?.handleVoiceRecognitionResult(result)
                    }
                }
            )
        } catch {
            ScreenSenseLogger.voice.error("Failed to start listening: \(error.localizedDescription)")
            state = .failed(error: error.localizedDescription)
            audioFeedback.playSound(.failure)
        }
    }

    public func stopListening() {
        voiceManager.stopListening()
    }

    private func handleVoiceRecognitionResult(_ result: Result<String, Error>) {
        switch result {
        case .success(let transcript):
            currentTranscript = transcript
            ScreenSenseLogger.recognition.info("Final transcript: '\(transcript, privacy: .public)'")
            processTranscript(transcript)

        case .failure(let error):
            ScreenSenseLogger.recognition.error("Voice recognition failed: \(error.localizedDescription)")
            state = .failed(error: error.localizedDescription)
            audioFeedback.playSound(.failure)
            scheduleStateReset(delay: 3.0)
        }
    }

    public func processTranscript(_ transcript: String) {
        state = .processing(transcript: transcript)

        let parseResult = commandParser.parse(transcript: transcript)
        switch parseResult {
        case .success(let command):
            lastCommandDescription = command.description
            ScreenSenseLogger.parser.info("Parsed command: \(command.description, privacy: .public)")
            executeCommand(command)

        case .empty:
            ScreenSenseLogger.parser.info("Empty transcript received")
            state = .idle

        case .unsupported(let raw, let reason):
            ScreenSenseLogger.parser.warning("Unsupported command: '\(raw, privacy: .public)' - \(reason)")
            state = .failed(error: reason)
            audioFeedback.playSound(.failure)
            scheduleStateReset(delay: 3.0)
        }
    }

    private func executeCommand(_ command: AnyCommand) {
        let context = CommandExecutionContext(
            pasteManager: pasteManager,
            clipboardManager: clipboardManager
        )

        Task {
            do {
                let result = try await command.execute(context: context)
                if result.success {
                    lastExecutionMessage = result.message
                    state = .executed(command: command.description, message: result.message)
                    audioFeedback.playSound(.success)
                    ScreenSenseLogger.app.info("Command executed successfully: \(command.description)")
                } else {
                    lastExecutionMessage = result.message
                    state = .failed(error: result.message)
                    audioFeedback.playSound(.failure)
                    ScreenSenseLogger.app.error("Command execution failed: \(result.message)")
                }
            } catch {
                lastExecutionMessage = error.localizedDescription
                state = .failed(error: error.localizedDescription)
                audioFeedback.playSound(.failure)
                ScreenSenseLogger.app.error("Command execution threw error: \(error.localizedDescription)")
            }

            scheduleStateReset(delay: 3.0)
        }
    }

    private func scheduleStateReset(delay: TimeInterval) {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if case .listening = self.state {
                return
            }
            self.state = .idle
        }
    }
}
