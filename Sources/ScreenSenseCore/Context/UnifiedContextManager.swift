import Foundation
import AppKit
import Combine

/// Protocol for the universal UnifiedContext manager
public protocol UnifiedContextManagerProtocol: AnyObject, Sendable {
    var latestContext: UnifiedContext? { get }
    var currentApplicationName: String { get }
    var contextStatusDescription: String { get }
    var activeTabTitle: String { get }
    var isReady: Bool { get }
    var fallbackReason: String? { get }
    var isBridgeConnected: Bool { get }
    var onContextUpdated: (@Sendable (UnifiedContext) -> Void)? { get set }

    func getUnifiedContext() async -> UnifiedContext
    func refreshContext() async -> UnifiedContext
    func startMonitoring()
    func stopMonitoring()

    /// Live Command-Time Queries
    func queryActiveTab(timeout: TimeInterval) async throws -> LiveQueryResponse
    func queryActivePointer(timeout: TimeInterval) async throws -> LivePointerResult
    func queryActiveSelection(timeout: TimeInterval) async throws -> LiveSelectionResult
    func queryActiveDOM(timeout: TimeInterval) async throws -> VisibleContext
}

/// Central manager orchestrating multi-source context acquisition, freshness, and automatic synchronization
public final class UnifiedContextManager: UnifiedContextManagerProtocol, @unchecked Sendable {
    public private(set) var latestContext: UnifiedContext?
    public private(set) var currentApplicationName: String = "Finder"
    public private(set) var fallbackReason: String?
    public private(set) var domAttempted: Bool = false
    public var onContextUpdated: (@Sendable (UnifiedContext) -> Void)?

    public var isBridgeConnected: Bool {
        browserBridge.isConnected
    }

    public var activeTabTitle: String {
        lock.lock()
        defer { lock.unlock() }
        return latestContext?.activeTabTitle ?? "—"
    }

    private let browserBridge: BrowserBridgeProtocol
    private let accessibilityProvider: AccessibilityContextProviderProtocol?
    private let screenCaptureProvider: ScreenCaptureContextProviderProtocol

    private var appSwitchObserver: NSObjectProtocol?
    private let lock = NSLock()

    public init(
        browserBridge: BrowserBridgeProtocol = LocalBrowserBridge(),
        accessibilityProvider: AccessibilityContextProviderProtocol? = nil,
        screenCaptureProvider: ScreenCaptureContextProviderProtocol = ScreenCaptureContextProvider()
    ) {
        self.browserBridge = browserBridge
        self.accessibilityProvider = accessibilityProvider
        self.screenCaptureProvider = screenCaptureProvider

        // Automatically update context when Chrome DOM arrives via bridge
        self.browserBridge.onContextReceived = { [weak self] domContext in
            self?.handleLiveDOMUpdate(domContext)
        }
    }

    public var isReady: Bool {
        latestContext != nil
    }

    public var contextStatusDescription: String {
        lock.lock()
        defer { lock.unlock() }

        guard let ctx = latestContext else {
            return "No Context Captured Yet"
        }

        let isChrome = currentApplicationName.contains("Chrome") || currentApplicationName.contains("Chromium")

        if ctx.source == .dom {
            return "Chrome DOM • \(ctx.elements.count) elements (\(ctx.freshnessState.rawValue.capitalized))"
        } else if ctx.source == .ocr {
            if isChrome, let reason = fallbackReason {
                return "Screen Capture (OCR) • \(ctx.elements.count) elements (Fallback: \(reason))"
            }
            return "Screen Capture (OCR) • \(ctx.elements.count) elements (\(ctx.freshnessState.rawValue.capitalized))"
        } else {
            return "\(ctx.source.rawValue.capitalized) • \(ctx.elements.count) elements (\(ctx.freshnessState.rawValue.capitalized))"
        }
    }

    public func startMonitoring() {
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.handleApplicationActivated(app)
            }
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            handleApplicationActivated(frontmost)
        }

        ScreenSenseLogger.context.info("UnifiedContextManager monitoring active.")
    }

    public func stopMonitoring() {
        if let obs = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appSwitchObserver = nil
        }
    }

    private func handleLiveDOMUpdate(_ dom: VisibleContext) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let appName = frontmost?.localizedName ?? currentApplicationName
        let bundleId = frontmost?.bundleIdentifier ?? ""
        let isChrome = bundleId.contains("Chrome") || appName.contains("Chrome") || bundleId.contains("Chromium")

        let resolvedAppName = isChrome ? appName : "Google Chrome"
        let unified = UnifiedContext.fromDOMContext(dom, appName: resolvedAppName)
        
        let callback: (@Sendable (UnifiedContext) -> Void)?
        lock.lock()
        self.currentApplicationName = resolvedAppName
        self.latestContext = unified
        self.fallbackReason = nil
        callback = self.onContextUpdated
        lock.unlock()

        callback?(unified)

        ScreenSenseLogger.context.info("[SS-TAB-SYNC] UnifiedContextManager.handleLiveDOMUpdate() updated latestContext: \(unified.elements.count) elements, app: \(resolvedAppName, privacy: .public), title: '\(unified.windowInfo?.title ?? "none", privacy: .public)', tabId: \(dom.metadata["tab_id"] ?? "unknown", privacy: .public)")
        ScreenSenseLogger.context.info("[SS-VIEWPORT-SYNC] UnifiedContextManager received update scrollY=\(Int(unified.viewport?.scrollY ?? 0)) elements=\(unified.elements.count)")
    }

    private func getCachedFreshContext(for appName: String, isChrome: Bool) -> UnifiedContext? {
        lock.lock()
        defer { lock.unlock() }

        guard let existing = latestContext else { return nil }

        // If Chrome is active, an OCR context must NEVER be returned as a valid cached context
        if isChrome && existing.source != .dom {
            return nil
        }

        if existing.freshnessState == .fresh {
            return existing
        }
        return nil
    }

    private func setApplicationName(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        self.currentApplicationName = name
    }

    private func updateStoredContext(_ context: UnifiedContext, reason: String? = nil) {
        let callback: (@Sendable (UnifiedContext) -> Void)?
        lock.lock()
        self.latestContext = context
        self.fallbackReason = reason
        callback = self.onContextUpdated
        lock.unlock()

        callback?(context)
    }

    public func setCurrentApplication(name: String) {
        setApplicationName(name)
    }

    public func getUnifiedContext() async -> UnifiedContext {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let appName = frontmost?.localizedName ?? currentApplicationName
        let bundleId = frontmost?.bundleIdentifier ?? ""
        let isChrome = bundleId.contains("Chrome") || appName.contains("Chrome") || bundleId.contains("Chromium") || currentApplicationName.contains("Chrome") || (browserBridge.latestDOMContext != nil && !(browserBridge.latestDOMContext?.elements.isEmpty ?? true))

        if let existing = getCachedFreshContext(for: isChrome ? "Google Chrome" : appName, isChrome: isChrome) {
            return existing
        }
        return await refreshContext()
    }

    public func refreshContext() async -> UnifiedContext {
        await refreshContext(targetAppName: nil)
    }

    public func refreshContext(targetAppName: String?) async -> UnifiedContext {
        let frontmost = NSWorkspace.shared.frontmostApplication
        var appName = targetAppName ?? ((currentApplicationName != "Finder" && currentApplicationName != "Desktop") ? currentApplicationName : (frontmost?.localizedName ?? "Desktop"))
        let bundleId = (appName.contains("Chrome") || targetAppName != nil) ? "com.google.Chrome" : (frontmost?.bundleIdentifier ?? "")

        let isExplicitNonChrome = targetAppName != nil && !targetAppName!.contains("Chrome") && !targetAppName!.contains("Chromium")
        let isChrome = !isExplicitNonChrome && (bundleId.contains("Chrome") || appName.contains("Chrome") || bundleId.contains("Chromium") || currentApplicationName.contains("Chrome") || (browserBridge.latestDOMContext != nil && !(browserBridge.latestDOMContext?.elements.isEmpty ?? true)))

        if isChrome && (appName == "Finder" || appName == "Desktop" || appName.contains("ScreenSense") || appName == "xctest") {
            appName = "Google Chrome"
        }

        setApplicationName(appName)

        // 1. Chrome Priority: Chrome Extension DOM -> Screen Capture/OCR Genuine Fallback
        if isChrome {
            domAttempted = true
            let bridgeConnected = browserBridge.isConnected
            let domContext = browserBridge.latestDOMContext

            ScreenSenseLogger.context.info("""
            [DIAGNOSTIC] Chrome frontmost detected:
            - BundleId: \(bundleId, privacy: .public)
            - Bridge Connected: \(bridgeConnected)
            - DOM Payload Exists: \(domContext != nil)
            - DOM Element Count: \(domContext?.elements.count ?? 0)
            - DOM Context Timestamp: \(String(describing: domContext?.timestamp))
            """)

            if let dom = domContext, !dom.elements.isEmpty {
                let unified = UnifiedContext.fromDOMContext(dom, appName: appName)
                updateStoredContext(unified, reason: nil)
                ScreenSenseLogger.context.info("[CONTEXT SYNC] Active: \(appName, privacy: .public) -> Using Chrome DOM (\(dom.elements.count) elements). OCR NOT invoked.")
                return unified
            }

            // Fallback reason diagnosis
            let reason: String
            if !bridgeConnected {
                reason = "Chrome extension bridge not connected on port 41920"
            } else if domContext == nil {
                reason = "No DOM payload received from Chrome extension"
            } else {
                reason = "DOM payload contains 0 visible elements"
            }

            ScreenSenseLogger.context.warning("[CONTEXT SYNC] Chrome DOM unavailable (\(reason, privacy: .public)). Falling back to Screen OCR.")

            if let ocrContext = await screenCaptureProvider.extractContext(for: frontmost) {
                updateStoredContext(ocrContext, reason: reason)
                ScreenSenseLogger.context.info("[CONTEXT SYNC] Active: \(appName, privacy: .public) -> Fallback to Screen OCR (\(ocrContext.elements.count) elements)")
                return ocrContext
            }

            let empty = UnifiedContext(
                source: .ocr,
                applicationName: appName,
                windowInfo: WindowInfo(title: "Active Window", appName: appName, bundleId: bundleId),
                elements: [],
                largeTextRegions: []
            )
            updateStoredContext(empty, reason: reason)
            return empty
        }

        // 2. Native Application Priority: Screen Capture + Apple Vision OCR
        domAttempted = false
        if let ocrContext = await screenCaptureProvider.extractContext(for: frontmost) {
            updateStoredContext(ocrContext, reason: nil)
            ScreenSenseLogger.context.info("[CONTEXT SYNC] Active: \(appName, privacy: .public) -> Using Screen OCR (\(ocrContext.elements.count) elements)")
            return ocrContext
        }

        // 3. Fallback Empty Context
        let empty = UnifiedContext(
            source: .ocr,
            applicationName: appName,
            windowInfo: WindowInfo(title: "Active Window", appName: appName, bundleId: bundleId),
            elements: [],
            largeTextRegions: []
        )
        updateStoredContext(empty, reason: nil)
        return empty
    }

    private func handleApplicationActivated(_ app: NSRunningApplication) {
        let appName = app.localizedName ?? "Application"
        setApplicationName(appName)

        Task {
            _ = await self.refreshContext()
        }
    }

    // MARK: - Live Query Delegation

    public func queryActiveTab(timeout: TimeInterval = 0.5) async throws -> LiveQueryResponse {
        try await browserBridge.queryActiveTab(timeout: timeout)
    }

    public func queryActivePointer(timeout: TimeInterval = 0.5) async throws -> LivePointerResult {
        try await browserBridge.queryActivePointer(timeout: timeout)
    }

    public func queryActiveSelection(timeout: TimeInterval = 0.5) async throws -> LiveSelectionResult {
        try await browserBridge.queryActiveSelection(timeout: timeout)
    }

    public func queryActiveDOM(timeout: TimeInterval = 1.0) async throws -> VisibleContext {
        try await browserBridge.queryActiveDOM(timeout: timeout)
    }
}
