import XCTest
import CoreGraphics
@testable import ScreenSenseCore

final class ContextFusionTests: XCTestCase {
    var fusion: ContextFusion!

    override func setUp() {
        super.setUp()
        fusion = ContextFusion()
    }

    override func tearDown() {
        fusion = nil
        super.tearDown()
    }

    func testFusionDOMOnly() {
        let el = VisibleElement(
            id: "el-1",
            type: .paragraph,
            text: "DOM Element",
            bounds: ElementBounds(x: 10, y: 20, width: 200, height: 40)
        )
        let dom = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1000, height: 700, pageTitle: "Test Page"),
            elements: [el]
        )

        let fused = fusion.fuse(dom: dom, screen: nil)

        XCTAssertEqual(fused.source, .unified)
        XCTAssertEqual(fused.elements.count, 1)
        XCTAssertEqual(fused.elements.first?.text, "DOM Element")
        XCTAssertEqual(fused.viewport.pageTitle, "Test Page")
        XCTAssertNil(fused.screenshot)
        XCTAssertEqual(fused.metadata["fusion_type"], "dom_plus_screen")
    }

    func testFusionScreenOnly() {
        // Create 1x1 test CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 40,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cgImage = context.makeImage()!

        let screenResult = ScreenCaptureResult(
            image: cgImage,
            width: 1920,
            height: 1080,
            scaleFactor: 2.0,
            windowTitle: "Xcode Window",
            applicationName: "Xcode"
        )

        let fused = fusion.fuse(dom: nil, screen: screenResult)

        XCTAssertEqual(fused.source, .screen)
        XCTAssertEqual(fused.elements.count, 0)
        XCTAssertNotNil(fused.screenshot)
        XCTAssertEqual(fused.screenshot?.width, 1920)
        XCTAssertEqual(fused.screenshot?.appName, "Xcode")
        XCTAssertEqual(fused.metadata["active_app"], "Xcode")
    }

    func testFusionDOMAndScreenCombined() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 40,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cgImage = context.makeImage()!

        let screenResult = ScreenCaptureResult(
            image: cgImage,
            width: 2560,
            height: 1440,
            scaleFactor: 2.0,
            windowTitle: "Wikipedia Article",
            applicationName: "Google Chrome"
        )

        let el1 = VisibleElement(id: "h1", type: .heading, text: "Wikipedia Title", bounds: ElementBounds(x: 0, y: 10, width: 500, height: 40))
        let el2 = VisibleElement(id: "p1", type: .paragraph, text: "Wikipedia Body", bounds: ElementBounds(x: 0, y: 60, width: 500, height: 80))
        let dom = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1280, height: 800, pageTitle: "Wikipedia"),
            elements: [el1, el2]
        )

        let fused = fusion.fuse(dom: dom, screen: screenResult)

        XCTAssertEqual(fused.source, .unified)
        XCTAssertEqual(fused.elements.count, 2)
        XCTAssertNotNil(fused.screenshot)
        XCTAssertEqual(fused.screenshot?.appName, "Google Chrome")
        XCTAssertEqual(fused.metadata["active_app"], "Google Chrome")
        XCTAssertEqual(fused.metadata["dom_element_count"], "2")
    }
}
