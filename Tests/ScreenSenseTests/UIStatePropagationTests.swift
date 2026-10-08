import XCTest
import Combine
@testable import ScreenSenseCore

final class UIStateMockBrowserBridge: BrowserBridgeProtocol, @unchecked Sendable {
    var isConnected: Bool = true
    var latestDOMContext: VisibleContext?
    var onContextReceived: (@Sendable (VisibleContext) -> Void)?

    func start() throws {}
    func stop() {}
    func broadcastMessage(_ message: [String: Any]) {}

    func simulateDOMArrival(_ context: VisibleContext) {
        self.latestDOMContext = context
        self.onContextReceived?(context)
    }
}

final class UIStateMockScreenCaptureProvider: ScreenCaptureContextProviderProtocol, @unchecked Sendable {
    var contextToReturn: UnifiedContext?

    func extractContext(for runningApp: NSRunningApplication?) async -> UnifiedContext? {
        return contextToReturn
    }
}

@MainActor
final class UIStatePropagationTests: XCTestCase {
    nonisolated(unsafe) var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testInitialChromeContextTabTitleAndApp() async {
        let bridge = UIStateMockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: bridge)
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        let initialDOM = VisibleContext(
            id: "ctx-1",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, pageTitle: "Quantum computing — Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
            elements: (1...122).map {
                VisibleElement(id: "el-\($0)", type: .paragraph, text: "Quantum text \($0)", bounds: ElementBounds(x: 10, y: Double($0 * 20), width: 200, height: 18))
            }
        )

        bridge.simulateDOMArrival(initialDOM)
        // Give MainActor task a microtick
        await Task.yield()

        XCTAssertEqual(coordinator.currentApplicationName, "Google Chrome")
        XCTAssertEqual(coordinator.activeTabTitle, "Quantum computing — Wikipedia")
        XCTAssertTrue(coordinator.contextStatusDescription.contains("122 elements"))
        XCTAssertTrue(coordinator.contextStatusDescription.contains("Chrome DOM"))
    }

    func testLiveDOMUpdateImmediateUIStateChange() async {
        let bridge = UIStateMockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: bridge)
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        // 1. Initial Tab A
        let tabA = VisibleContext(
            id: "ctx-tab-a",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, pageTitle: "Quantum computing — Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
            elements: (1...122).map {
                VisibleElement(id: "el-\($0)", type: .paragraph, text: "Quantum text \($0)", bounds: ElementBounds(x: 10, y: Double($0 * 20), width: 200, height: 18))
            }
        )
        bridge.simulateDOMArrival(tabA)
        await Task.yield()

        XCTAssertEqual(coordinator.activeTabTitle, "Quantum computing — Wikipedia")
        XCTAssertEqual(coordinator.latestUnifiedContext?.elements.count, 122)

        // 2. Switch to Tab B
        let tabB = VisibleContext(
            id: "ctx-tab-b",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, pageTitle: "Alan Turing — Wikipedia", url: "https://en.wikipedia.org/wiki/Alan_Turing"),
            elements: (1...184).map {
                VisibleElement(id: "el-\($0)", type: .paragraph, text: "Turing text \($0)", bounds: ElementBounds(x: 10, y: Double($0 * 20), width: 200, height: 18))
            }
        )
        bridge.simulateDOMArrival(tabB)
        await Task.yield()

        XCTAssertEqual(coordinator.activeTabTitle, "Alan Turing — Wikipedia")
        XCTAssertEqual(coordinator.latestUnifiedContext?.elements.count, 184)
        XCTAssertTrue(coordinator.contextStatusDescription.contains("184 elements"))
    }

    func testContinuousTabSwitchingCycles() async {
        let bridge = UIStateMockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: bridge)
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        let tabA = VisibleContext(
            id: "ctx-tab-a",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, pageTitle: "Quantum computing — Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
            elements: Array(repeating: VisibleElement(id: "1", type: .paragraph, text: "A", bounds: ElementBounds(x: 0, y: 0, width: 10, height: 10)), count: 122)
        )

        let tabB = VisibleContext(
            id: "ctx-tab-b",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, pageTitle: "Alan Turing — Wikipedia", url: "https://en.wikipedia.org/wiki/Alan_Turing"),
            elements: Array(repeating: VisibleElement(id: "2", type: .paragraph, text: "B", bounds: ElementBounds(x: 0, y: 0, width: 10, height: 10)), count: 184)
        )

        // Rapid cycling A -> B -> A -> B -> A
        for _ in 1...5 {
            bridge.simulateDOMArrival(tabA)
            await Task.yield()
            XCTAssertEqual(coordinator.activeTabTitle, "Quantum computing — Wikipedia")
            XCTAssertEqual(coordinator.latestUnifiedContext?.elements.count, 122)

            bridge.simulateDOMArrival(tabB)
            await Task.yield()
            XCTAssertEqual(coordinator.activeTabTitle, "Alan Turing — Wikipedia")
            XCTAssertEqual(coordinator.latestUnifiedContext?.elements.count, 184)
        }
    }

    func testSourceChangeFromDOMToOCRUpdatesContextStatus() async {
        let bridge = UIStateMockBrowserBridge()
        let sckProvider = UIStateMockScreenCaptureProvider()
        let manager = UnifiedContextManager(
            browserBridge: bridge,
            screenCaptureProvider: sckProvider
        )
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        // 1. Chrome DOM active
        let dom = VisibleContext(
            id: "ctx-dom",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, pageTitle: "Documentation", url: "https://developer.apple.com"),
            elements: [VisibleElement(id: "1", type: .heading, text: "SwiftUI", bounds: ElementBounds(x: 0, y: 0, width: 100, height: 30))]
        )
        bridge.simulateDOMArrival(dom)
        await Task.yield()
        XCTAssertTrue(coordinator.contextStatusDescription.contains("Chrome DOM"))

        // 2. Switch to native app (OCR)
        sckProvider.contextToReturn = UnifiedContext(
            source: .ocr,
            applicationName: "Xcode",
            windowInfo: WindowInfo(title: "ScreenSense.xcodeproj", appName: "Xcode"),
            elements: [VisibleElement(id: "ocr-1", type: .genericText, text: "func main()", bounds: ElementBounds(x: 10, y: 10, width: 100, height: 20), source: .ocr)]
        )

        _ = await manager.refreshContext(targetAppName: "Xcode")
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(coordinator.currentApplicationName, "Xcode")
        XCTAssertEqual(coordinator.activeTabTitle, "ScreenSense.xcodeproj")
        XCTAssertTrue(coordinator.contextStatusDescription.contains("Screen Capture (OCR)"))
    }

    func testActiveTabIdentityPriorityRules() {
        // Priority 1: viewport.pageTitle
        let ctx1 = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: WindowInfo(title: "Window Title", appName: "Google Chrome"),
            viewport: ViewportInfo(width: 1000, height: 800, pageTitle: "Viewport Page Title", url: "https://example.com/page"),
            elements: [],
            metadata: ["page_title": "Meta Title"]
        )
        XCTAssertEqual(ctx1.activeTabTitle, "Viewport Page Title")

        // Priority 2: metadata["page_title"] if viewport.pageTitle is nil or empty
        let ctx2 = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: WindowInfo(title: "Window Title", appName: "Google Chrome"),
            viewport: ViewportInfo(width: 1000, height: 800, pageTitle: "", url: "https://example.com/page"),
            elements: [],
            metadata: ["page_title": "Meta Title"]
        )
        XCTAssertEqual(ctx2.activeTabTitle, "Meta Title")

        // Priority 3: windowInfo.title if pageTitle & meta are missing
        let ctx3 = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: WindowInfo(title: "Specific Window Title", appName: "Google Chrome"),
            viewport: nil,
            elements: [],
            metadata: [:]
        )
        XCTAssertEqual(ctx3.activeTabTitle, "Specific Window Title")

        // Priority 4: URL fallback if windowInfo is generic
        let ctx4 = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: WindowInfo(title: "Google Chrome", appName: "Google Chrome"),
            viewport: ViewportInfo(width: 1000, height: 800, pageTitle: nil, url: "https://developer.apple.com/documentation"),
            elements: [],
            metadata: [:]
        )
        XCTAssertEqual(ctx4.activeTabTitle, "developer.apple.com/documentation")

        // Non-Chrome App without window title returns "—"
        let ctx5 = UnifiedContext(
            source: .ocr,
            applicationName: "Finder",
            windowInfo: nil,
            elements: []
        )
        XCTAssertEqual(ctx5.activeTabTitle, "—")
    }

    func testBackgroundCallbackSafelyPropagatesToMainActor() async {
        let bridge = UIStateMockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: bridge)
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        let expectation = expectation(description: "Context arrived on MainActor")

        coordinator.$latestUnifiedContext
            .compactMap { $0 }
            .filter { $0.viewport?.pageTitle == "Async Page" }
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Dispatch simulated bridge update from background thread
        DispatchQueue.global(qos: .background).async {
            let asyncDOM = VisibleContext(
                id: "async-ctx",
                source: .dom,
                viewport: ViewportInfo(width: 1000, height: 800, pageTitle: "Async Page", url: "https://async.test"),
                elements: [VisibleElement(id: "1", type: .heading, text: "Background Arrival", bounds: ElementBounds(x: 0, y: 0, width: 100, height: 20))]
            )
            bridge.simulateDOMArrival(asyncDOM)
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(coordinator.activeTabTitle, "Async Page")
    }
}
