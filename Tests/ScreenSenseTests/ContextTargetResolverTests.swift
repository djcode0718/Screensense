import XCTest
@testable import ScreenSenseCore

final class ContextTargetResolverTests: XCTestCase {
    var resolver: ContextTargetResolver!

    override func setUp() {
        super.setUp()
        resolver = ContextTargetResolver()
    }

    override func tearDown() {
        resolver = nil
        super.tearDown()
    }

    func testResolveExplicitParagraph() {
        let p1 = VisibleElement(id: "p-1", type: .paragraph, text: "First paragraph.", bounds: ElementBounds(x: 10, y: 10, width: 200, height: 30))
        let p2 = VisibleElement(id: "p-2", type: .paragraph, text: "Second paragraph.", bounds: ElementBounds(x: 10, y: 50, width: 200, height: 30))

        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: nil,
            elements: [p1, p2],
            largeTextRegions: []
        )

        // Resolve paragraph 2
        let res = resolver.resolve(target: .element(type: .paragraph, index: 2), in: context)
        if case .success(let el, let txt) = res {
            XCTAssertEqual(el?.id, "p-2")
            XCTAssertEqual(txt, "Second paragraph.")
        } else {
            XCTFail("Expected .success for paragraph 2")
        }

        // Out of bounds paragraph 3
        let outOfBounds = resolver.resolve(target: .element(type: .paragraph, index: 3), in: context)
        if case .notFound = outOfBounds {
            // Success
        } else {
            XCTFail("Expected .notFound for out of bounds index")
        }
    }

    func testResolveWordRangeFromParagraph() {
        let p1 = VisibleElement(
            id: "p-1",
            type: .paragraph,
            text: "ScreenSense is the premier context-aware voice assistant for macOS.",
            bounds: ElementBounds(x: 10, y: 10, width: 400, height: 30)
        )

        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: nil,
            elements: [p1],
            largeTextRegions: []
        )

        // words 4 to 6 -> "premier context-aware voice"
        let res = resolver.resolve(
            target: .wordRange(scope: .element(type: .paragraph, index: 1), range: WordRange(start: 4, end: 6)),
            in: context
        )

        if case .success(_, let text) = res {
            XCTAssertEqual(text, "premier context-aware voice")
        } else {
            XCTFail("Expected .success for word range resolution")
        }
    }

    func testResolveSemanticPhoneNumber() {
        let p = VisibleElement(id: "p-1", type: .paragraph, text: "For customer support, call +1 (800) 555-0199 today.", bounds: ElementBounds(x: 10, y: 10, width: 400, height: 30))
        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: nil,
            elements: [p],
            largeTextRegions: []
        )

        let res = resolver.resolve(target: .semantic(role: "phone_number", topic: nil), in: context)
        if case .success(_, let text) = res {
            XCTAssertEqual(text, "+1 (800) 555-0199")
        } else {
            XCTFail("Expected phone number resolution")
        }
    }

    func testResolveSemanticTopicText() {
        let p1 = VisibleElement(id: "p-1", type: .paragraph, text: "About our company: Founded in 2024.", bounds: ElementBounds(x: 10, y: 10, width: 400, height: 30))
        let p2 = VisibleElement(id: "p-2", type: .paragraph, text: "Internship requirements include Swift and JavaScript.", bounds: ElementBounds(x: 10, y: 60, width: 400, height: 30))

        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: nil,
            elements: [p1, p2],
            largeTextRegions: []
        )

        let res = resolver.resolve(target: .semantic(role: "text_about", topic: "internship requirements"), in: context)
        if case .success(let el, _) = res {
            XCTAssertEqual(el?.id, "p-2")
        } else {
            XCTFail("Expected matching element for internship topic")
        }
    }
}
