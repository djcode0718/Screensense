import XCTest
import Combine
@testable import ScreenSenseCore

@MainActor
final class ViewportScrollSyncTests: XCTestCase {
    nonisolated(unsafe) var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // 1. Initial viewport scrollY = 0
    func testInitialViewportScrollZero() async {
        let bridge = UIStateMockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: bridge)
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        let initialDOM = VisibleContext(
            id: "ctx-top",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 0, pageTitle: "Quantum computing — Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
            elements: [
                VisibleElement(id: "h1", type: .heading, text: "Quantum computing", bounds: ElementBounds(x: 20, y: 30, width: 400, height: 40)),
                VisibleElement(id: "p1", type: .paragraph, text: "Quantum computing is a rapidly-emerging technology.", bounds: ElementBounds(x: 20, y: 80, width: 800, height: 60))
            ]
        )

        bridge.simulateDOMArrival(initialDOM)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(coordinator.latestUnifiedContext?.viewport?.scrollY, 0)
        XCTAssertEqual(coordinator.activeTabTitle, "Quantum computing — Wikipedia")
        XCTAssertEqual(coordinator.latestUnifiedContext?.elements.count, 2)
    }

    // 2. Scroll update: scrollY 0 -> 1000
    func testScrollUpdatePublishesNewContext() async {
        let bridge = UIStateMockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: bridge)
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        // Top of page
        let domTop = VisibleContext(
            id: "ctx-top",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 0, pageTitle: "Quantum computing — Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
            elements: [
                VisibleElement(id: "h1", type: .heading, text: "Quantum computing", bounds: ElementBounds(x: 20, y: 30, width: 400, height: 40))
            ]
        )
        bridge.simulateDOMArrival(domTop)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(coordinator.latestUnifiedContext?.viewport?.scrollY, 0)

        // Scrolled to 1000px
        let domScrolled = VisibleContext(
            id: "ctx-scroll-1000",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 1000, pageTitle: "Quantum computing — Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
            elements: [
                VisibleElement(id: "h2-algo", type: .heading, text: "Quantum algorithms", bounds: ElementBounds(x: 20, y: 40, width: 350, height: 35)),
                VisibleElement(id: "p-shor", type: .paragraph, text: "Shor's algorithm provides exponential speedup.", bounds: ElementBounds(x: 20, y: 85, width: 800, height: 60))
            ]
        )
        bridge.simulateDOMArrival(domScrolled)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(coordinator.latestUnifiedContext?.viewport?.scrollY, 1000)
        XCTAssertEqual(coordinator.activeTabTitle, "Quantum computing — Wikipedia")
        XCTAssertEqual(coordinator.latestUnifiedContext?.elements.count, 2)
        XCTAssertEqual(coordinator.latestUnifiedContext?.elements.first?.text, "Quantum algorithms")
    }

    // 3. Large scroll: scrollY 1000 -> 3000
    func testLargeScrollDown() async {
        let bridge = UIStateMockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: bridge)
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        let dom3000 = VisibleContext(
            id: "ctx-scroll-3000",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 3000, pageTitle: "Quantum computing — Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
            elements: [
                VisibleElement(id: "h2-hardware", type: .heading, text: "Physical implementations", bounds: ElementBounds(x: 20, y: 50, width: 350, height: 35)),
                VisibleElement(id: "p-superconduct", type: .paragraph, text: "Superconducting qubits operate at millikelvin temperatures.", bounds: ElementBounds(x: 20, y: 95, width: 800, height: 50))
            ]
        )
        bridge.simulateDOMArrival(dom3000)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(coordinator.latestUnifiedContext?.viewport?.scrollY, 3000)
        XCTAssertEqual(coordinator.latestContext?.viewport.scrollY, 3000)
        XCTAssertEqual(coordinator.latestUnifiedContext?.elements.last?.text, "Superconducting qubits operate at millikelvin temperatures.")
    }

    // 4. Visibility change: element becomes off-screen, new element appears
    func testVisibilityChangeDuringScroll() async {
        let bridge = UIStateMockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: bridge)
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        // Viewport 1: Element A is visible
        let elA = VisibleElement(id: "el-a", type: .paragraph, text: "Intro paragraph A", bounds: ElementBounds(x: 10, y: 100, width: 400, height: 30), visibilityPercentage: 1.0)
        let ctx1 = VisibleContext(
            id: "ctx-1",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 0, pageTitle: "Page"),
            elements: [elA]
        )
        bridge.simulateDOMArrival(ctx1)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(coordinator.latestUnifiedContext?.elements.map(\.id), ["el-a"])

        // Viewport 2: Scrolled down, Element A is gone, Element B is now visible
        let elB = VisibleElement(id: "el-b", type: .paragraph, text: "Deeper paragraph B", bounds: ElementBounds(x: 10, y: 150, width: 400, height: 30), visibilityPercentage: 1.0)
        let ctx2 = VisibleContext(
            id: "ctx-2",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 800, pageTitle: "Page"),
            elements: [elB]
        )
        bridge.simulateDOMArrival(ctx2)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(coordinator.latestUnifiedContext?.elements.map(\.id), ["el-b"])
        XCTAssertEqual(coordinator.latestUnifiedContext?.elements.first?.text, "Deeper paragraph B")
        XCTAssertEqual(coordinator.latestUnifiedContext?.viewport?.scrollY, 800)
    }

    // 5. Tab switch combined with different scroll positions
    func testTabSwitchWithScrollPositions() async {
        let bridge = UIStateMockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: bridge)
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        // Tab A at scrollY = 0
        let tabA = VisibleContext(
            id: "tab-a-ctx",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 0, pageTitle: "Quantum computing — Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
            elements: [VisibleElement(id: "a1", type: .heading, text: "Quantum computing", bounds: ElementBounds(x: 10, y: 10, width: 200, height: 30))]
        )
        bridge.simulateDOMArrival(tabA)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(coordinator.activeTabTitle, "Quantum computing — Wikipedia")
        XCTAssertEqual(coordinator.latestUnifiedContext?.viewport?.scrollY, 0)

        // Switch to Tab B at scrollY = 1500
        let tabB = VisibleContext(
            id: "tab-b-ctx",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 1500, pageTitle: "Alan Turing — Wikipedia", url: "https://en.wikipedia.org/wiki/Alan_Turing"),
            elements: [VisibleElement(id: "b1", type: .heading, text: "Turing machine", bounds: ElementBounds(x: 10, y: 10, width: 200, height: 30))]
        )
        bridge.simulateDOMArrival(tabB)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(coordinator.activeTabTitle, "Alan Turing — Wikipedia")
        XCTAssertEqual(coordinator.latestUnifiedContext?.viewport?.scrollY, 1500)
    }

    // 6. Rapid scrolling simulation (0 -> 200 -> 500 -> 1200 -> 2200)
    func testRapidScrollSequence() async {
        let bridge = UIStateMockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: bridge)
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        let scrollPositions: [Double] = [0, 200, 500, 900, 1500, 2200]
        for y in scrollPositions {
            let scrollCtx = VisibleContext(
                id: "ctx-\(Int(y))",
                source: .dom,
                viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: y, pageTitle: "Quantum computing — Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
                elements: [VisibleElement(id: "el-\(Int(y))", type: .paragraph, text: "Text at position \(Int(y))", bounds: ElementBounds(x: 10, y: 10, width: 200, height: 20))]
            )
            bridge.simulateDOMArrival(scrollCtx)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        // Final context must correspond to the final scroll position
        XCTAssertEqual(coordinator.latestUnifiedContext?.viewport?.scrollY, 2200)
        XCTAssertEqual(coordinator.latestUnifiedContext?.elements.first?.text, "Text at position 2200")
        XCTAssertEqual(coordinator.activeTabTitle, "Quantum computing — Wikipedia")
    }

    // 7. Scroll back to top restores top context
    func testScrollDownAndBackToTop() async {
        let bridge = UIStateMockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: bridge)
        let coordinator = ScreenSenseCoordinator(
            browserBridge: bridge,
            unifiedContextManager: manager
        )

        let topCtx = VisibleContext(
            id: "ctx-top",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 0, pageTitle: "Wiki Page"),
            elements: [VisibleElement(id: "top-el", type: .heading, text: "Top Heading", bounds: ElementBounds(x: 0, y: 0, width: 200, height: 30))]
        )
        bridge.simulateDOMArrival(topCtx)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(coordinator.latestUnifiedContext?.viewport?.scrollY, 0)

        let bottomCtx = VisibleContext(
            id: "ctx-bottom",
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 3500, pageTitle: "Wiki Page"),
            elements: [VisibleElement(id: "bot-el", type: .heading, text: "References", bounds: ElementBounds(x: 0, y: 0, width: 200, height: 30))]
        )
        bridge.simulateDOMArrival(bottomCtx)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(coordinator.latestUnifiedContext?.viewport?.scrollY, 3500)

        // Scroll back to top
        bridge.simulateDOMArrival(topCtx)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(coordinator.latestUnifiedContext?.viewport?.scrollY, 0)
        XCTAssertEqual(coordinator.latestUnifiedContext?.elements.first?.text, "Top Heading")
    }
}
