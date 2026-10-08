import Foundation
import Combine
import AppKit

/// Main Orchestrator for ScreenSense (Phase 1 & Phase 2)
@MainActor
public final class ScreenSenseCoordinator: ObservableObject {
    @Published public private(set) var state: ScreenSenseState = .idle
    @Published public private(set) var permissionStatus: PermissionStatus = PermissionStatus()
    @Published public private(set) var currentTranscript: String = ""
    @Published public private(set) var lastCommandDescription: String = ""
    @Published public private(set) var lastExecutionMessage: String = ""
    @Published public private(set) var latestContext: VisibleContext?
    @Published public private(set) var latestUnifiedContext: UnifiedContext?
    @Published public private(set) var isBridgeRunning: Bool = false

    private let hotkeyManager: HotkeyManagerProtocol
    private let voiceManager: VoiceManagerProtocol
    private let commandParser: CommandParserProtocol
    private let pasteManager: PasteManagerProtocol
    private let clipboardManager: ClipboardManagerProtocol
    private let permissionManager: PermissionManagerProtocol
    private let audioFeedback: AudioFeedbackProtocol
    private let screenCaptureProvider: ScreenCaptureProviderProtocol
    private let browserBridge: BrowserBridgeProtocol
    private let domContextProvider: DOMContextProviderProtocol
    private let contextFusion: ContextFusionProtocol
    public let unifiedContextManager: UnifiedContextManagerProtocol

    public var currentApplicationName: String {
        latestUnifiedContext?.applicationName ?? unifiedContextManager.currentApplicationName
    }

    public var activeTabTitle: String {
        latestUnifiedContext?.activeTabTitle ?? unifiedContextManager.activeTabTitle
    }

    public var contextStatusDescription: String {
        guard let ctx = latestUnifiedContext ?? unifiedContextManager.latestContext else {
            return "No Context Captured Yet"
        }

        let isChrome = currentApplicationName.contains("Chrome") || currentApplicationName.contains("Chromium")

        if ctx.source == .dom {
            return "Chrome DOM • \(ctx.elements.count) elements (\(ctx.freshnessState.rawValue.capitalized))"
        } else if ctx.source == .ocr {
            if isChrome, let reason = unifiedContextManager.fallbackReason {
                return "Screen Capture (OCR) • \(ctx.elements.count) elements (Fallback: \(reason))"
            }
            return "Screen Capture (OCR) • \(ctx.elements.count) elements (\(ctx.freshnessState.rawValue.capitalized))"
        } else {
            return "\(ctx.source.rawValue.capitalized) • \(ctx.elements.count) elements (\(ctx.freshnessState.rawValue.capitalized))"
        }
    }

    public init(
        hotkeyManager: HotkeyManagerProtocol = CarbonHotkeyManager(),
        voiceManager: VoiceManagerProtocol = VoiceManager(),
        commandParser: CommandParserProtocol = DeterministicCommandParser(),
        pasteManager: PasteManagerProtocol = PasteManager(),
        clipboardManager: ClipboardManagerProtocol = SystemClipboardManager(),
        permissionManager: PermissionManagerProtocol = PermissionManager(),
        audioFeedback: AudioFeedbackProtocol = SystemAudioFeedback(),
        screenCaptureProvider: ScreenCaptureProviderProtocol = SCKScreenCaptureProvider(),
        browserBridge: BrowserBridgeProtocol = LocalBrowserBridge(),
        contextFusion: ContextFusionProtocol = ContextFusion(),
        unifiedContextManager: UnifiedContextManagerProtocol? = nil
    ) {
        self.hotkeyManager = hotkeyManager
        self.voiceManager = voiceManager
        self.commandParser = commandParser
        self.pasteManager = pasteManager
        self.clipboardManager = clipboardManager
        self.permissionManager = permissionManager
        self.audioFeedback = audioFeedback
        self.screenCaptureProvider = screenCaptureProvider
        self.browserBridge = browserBridge
        self.domContextProvider = DOMContextProvider(bridge: browserBridge)
        self.contextFusion = contextFusion
        let manager = unifiedContextManager ?? UnifiedContextManager(
            browserBridge: browserBridge,
            screenCaptureProvider: ScreenCaptureContextProvider(captureProvider: screenCaptureProvider)
        )
        self.unifiedContextManager = manager
        self.latestUnifiedContext = manager.latestContext

        // Wire live context propagation to MainActor-isolated published properties
        self.unifiedContextManager.onContextUpdated = { [weak self] ctx in
            Task { @MainActor in
                self?.latestUnifiedContext = ctx
                let visibleCtx = VisibleContext(
                    id: ctx.id,
                    source: ctx.source,
                    timestamp: ctx.timestamp,
                    viewport: ctx.viewport ?? ViewportInfo(width: 1920, height: 1080, scrollX: 0, scrollY: 0, devicePixelRatio: 1.0, pageTitle: ctx.activeTabTitle, url: ctx.viewport?.url),
                    elements: ctx.elements,
                    screenshot: nil,
                    metadata: ctx.metadata
                )
                self?.latestContext = visibleCtx
                ScreenSenseLogger.app.info("[SS-VIEWPORT-SYNC] coordinator published context title='\(ctx.activeTabTitle, privacy: .public)' scrollY=\(Int(ctx.viewport?.scrollY ?? 0))")
            }
        }
    }

    public func start() {
        ScreenSenseLogger.app.info("Starting ScreenSense Coordinator...")
        refreshPermissions()
        registerGlobalHotkey()
        startBrowserBridge()
        unifiedContextManager.startMonitoring()
    }

    public func stop() {
        unifiedContextManager.stopMonitoring()
        hotkeyManager.unregister()
        voiceManager.stopListening()
        browserBridge.stop()
        isBridgeRunning = false
        state = .idle
        ScreenSenseLogger.app.info("ScreenSense Coordinator stopped")
    }

    public func startBrowserBridge() {
        do {
            try browserBridge.start()
            isBridgeRunning = true
            ScreenSenseLogger.app.info("Local browser bridge started successfully")
        } catch {
            isBridgeRunning = false
            ScreenSenseLogger.app.error("Failed to start browser bridge: \(error.localizedDescription)")
        }
    }

    public func refreshPermissions() {
        self.permissionStatus = permissionManager.checkAllPermissions()
        ScreenSenseLogger.permissions.info("Permissions status: Mic=\(self.permissionStatus.microphoneGranted), Speech=\(self.permissionStatus.speechRecognitionGranted), AX=\(self.permissionStatus.accessibilityGranted), Screen=\(self.permissionStatus.screenRecordingGranted)")
    }

    public func requestAllPermissions() async {
        _ = await permissionManager.requestMicrophonePermission()
        _ = await permissionManager.requestSpeechRecognitionPermission()
        _ = permissionManager.requestAccessibilityPermission()
        _ = permissionManager.requestScreenRecordingPermission()
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

        let normalized = StringNormalizer.normalize(transcript)
        let parserName = String(describing: type(of: commandParser))
        let parseResult = commandParser.parse(transcript: transcript)

        ScreenSenseLogger.parser.info("""
        [DEBUG RUNTIME PARSER]
        RAW SPEECH: '\(transcript, privacy: .public)'
        NORMALIZED SPEECH: '\(normalized, privacy: .public)'
        PARSER: \(parserName, privacy: .public)
        PARSED COMMAND: \(String(describing: parseResult), privacy: .public)
        """)

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
            clipboardManager: clipboardManager,
            domContextProvider: domContextProvider,
            semanticSelector: SemanticElementSelector(),
            unifiedContextManager: unifiedContextManager,
            targetResolver: ContextTargetResolver()
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

    // MARK: - Phase 2: Screen Context Engine Methods

    /// Captures a visual snapshot via ScreenCaptureKit
    public func captureScreenOnly() async throws -> ScreenCaptureResult {
        refreshPermissions()
        guard permissionStatus.screenRecordingGranted else {
            _ = permissionManager.requestScreenRecordingPermission()
            throw ScreenCaptureError.permissionDenied
        }

        let result = try await screenCaptureProvider.captureCurrentContext()
        let screenContext = contextFusion.fuse(dom: nil, screen: result)
        self.latestContext = screenContext
        return result
    }

    /// Fetches the latest DOM context sent from Chrome extension
    public func fetchDOMContextOnly() async -> VisibleContext? {
        let domContext = try? await domContextProvider.fetchCurrentDOMContext()
        if let dom = domContext {
            let fused = contextFusion.fuse(dom: dom, screen: nil)
            self.latestContext = fused
            return fused
        }
        return nil
    }

    /// Captures a unified context combining Chrome DOM and ScreenCaptureKit snapshot
    public func captureUnifiedContext() async throws -> VisibleContext {
        let dom = try? await domContextProvider.fetchCurrentDOMContext()

        var screenResult: ScreenCaptureResult? = nil
        if permissionManager.checkAllPermissions().screenRecordingGranted {
            screenResult = try? await screenCaptureProvider.captureCurrentContext()
        }

        let unified = contextFusion.fuse(dom: dom, screen: screenResult)
        self.latestContext = unified
        ScreenSenseLogger.app.info("Unified context captured: \(unified.elements.count) elements, source: \(unified.source.rawValue)")
        return unified
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
