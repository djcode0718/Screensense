import XCTest
@testable import ScreenSenseCore

final class LocalBrowserBridgeTests: XCTestCase {

    func testBridgeUpdateAndRetrieveContext() {
        let bridge = LocalBrowserBridge(port: 41925)
        XCTAssertNil(bridge.latestDOMContext)

        let element = VisibleElement(
            id: "el-bridge",
            type: .paragraph,
            text: "Bridge Test Element",
            bounds: ElementBounds(x: 10, y: 10, width: 200, height: 50)
        )
        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1000, height: 800),
            elements: [element]
        )

        bridge.updateContext(context)

        XCTAssertNotNil(bridge.latestDOMContext)
        XCTAssertEqual(bridge.latestDOMContext?.elements.count, 1)
        XCTAssertEqual(bridge.latestDOMContext?.elements.first?.text, "Bridge Test Element")
        XCTAssertTrue(bridge.isConnected)
    }

    func testDOMContextProviderDelegation() async throws {
        let bridge = LocalBrowserBridge(port: 41926)
        let provider = DOMContextProvider(bridge: bridge)

        let initial = try await provider.fetchCurrentDOMContext()
        XCTAssertNil(initial)

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 800, height: 600, pageTitle: "Provider Test"),
            elements: []
        )
        bridge.updateContext(context)

        let fetched = try await provider.fetchCurrentDOMContext()
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.viewport.pageTitle, "Provider Test")
    }
}
