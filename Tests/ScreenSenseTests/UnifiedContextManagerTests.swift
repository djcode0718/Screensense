import XCTest
@testable import ScreenSenseCore

final class UnifiedContextManagerTests: XCTestCase {
    func testFreshnessStateTransitions() {
        let freshTimestamp = Date()
        let freshContext = UnifiedContext(
            source: .dom,
            timestamp: freshTimestamp,
            applicationName: "Google Chrome",
            elements: [],
            largeTextRegions: []
        )
        XCTAssertEqual(freshContext.freshnessState, .fresh)

        let staleTimestamp = Date().addingTimeInterval(-25)
        let staleContext = UnifiedContext(
            source: .dom,
            timestamp: staleTimestamp,
            applicationName: "Google Chrome",
            elements: [],
            largeTextRegions: []
        )
        XCTAssertEqual(staleContext.freshnessState, .stale)

        let expiredTimestamp = Date().addingTimeInterval(-120)
        let expiredContext = UnifiedContext(
            source: .dom,
            timestamp: expiredTimestamp,
            applicationName: "Google Chrome",
            elements: [],
            largeTextRegions: []
        )
        XCTAssertEqual(expiredContext.freshnessState, .expired)
    }

    func testFromDOMContextConversion() {
        let p = VisibleElement(id: "p-1", type: .paragraph, text: "Sample text", bounds: ElementBounds(x: 10, y: 10, width: 100, height: 20))
        let dom = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900, pageTitle: "Test Page", url: "https://example.com"),
            elements: [p]
        )

        let unified = UnifiedContext.fromDOMContext(dom, appName: "Google Chrome")
        XCTAssertEqual(unified.source, .dom)
        XCTAssertEqual(unified.applicationName, "Google Chrome")
        XCTAssertEqual(unified.windowInfo?.title, "Test Page")
        XCTAssertEqual(unified.elements.count, 1)
        XCTAssertEqual(unified.largeTextRegions.count, 1)
        XCTAssertEqual(unified.largeTextRegions[0].text, "Sample text")
    }

    func testOCRContextTargetResolutionForWhatsAppMessage() {
        let resolver = ContextTargetResolver()

        // OCR elements representing a WhatsApp message
        let line1 = VisibleElement(id: "ocr-1", type: .genericText, text: "Rahul", bounds: ElementBounds(x: 50, y: 100, width: 60, height: 18), source: .ocr)
        let line2 = VisibleElement(id: "ocr-2", type: .genericText, text: "Hey, are you free tomorrow?", bounds: ElementBounds(x: 50, y: 122, width: 220, height: 20), source: .ocr)
        let line3 = VisibleElement(id: "ocr-3", type: .genericText, text: "10:30 PM", bounds: ElementBounds(x: 50, y: 145, width: 60, height: 14), source: .ocr)

        let region = TextRegion(
            id: "region-1",
            text: "Rahul\nHey, are you free tomorrow?\n10:30 PM",
            role: "paragraph",
            bounds: ElementBounds(x: 50, y: 100, width: 220, height: 60)
        )

        let ocrContext = UnifiedContext(
            source: .ocr,
            applicationName: "WhatsApp",
            windowInfo: WindowInfo(title: "WhatsApp - Rahul", appName: "WhatsApp", bundleId: "net.whatsapp.WhatsApp"),
            elements: [line1, line2, line3],
            largeTextRegions: [region]
        )

        // 1. Resolve explicit paragraph: "copy the first paragraph"
        let pRes = resolver.resolve(target: .element(type: .paragraph, index: 1), in: ocrContext)
        if case .success(_, let text) = pRes {
            XCTAssertTrue(text.contains("Hey, are you free tomorrow?"))
        } else {
            XCTFail("Expected explicit paragraph resolution in OCR context")
        }

        // 2. Resolve word range: "copy words 2 to 6 from the first paragraph"
        // region text tokens: ["Rahul", "Hey,", "are", "you", "free", "tomorrow?", "10:30", "PM"]
        let wRes = resolver.resolve(
            target: .wordRange(scope: .element(type: .paragraph, index: 1), range: WordRange(start: 2, end: 6)),
            in: ocrContext
        )
        if case .success(_, let text) = wRes {
            XCTAssertEqual(text, "Hey, are you free tomorrow?")
        } else {
            XCTFail("Expected word range resolution in OCR context")
        }

        // 3. Resolve text-to-text range: "copy from Hey to tomorrow"
        let tRes = resolver.resolve(
            target: .textRange(scope: nil, range: TextRange(startText: "Hey", endText: "tomorrow")),
            in: ocrContext
        )
        if case .success(_, let text) = tRes {
            XCTAssertTrue(text.contains("Hey, are you free tomorrow"))
        } else {
            XCTFail("Expected text range resolution in OCR context")
        }
    }

    func testOCRContextResolvesPriceAndEmailInNativeApp() {
        let resolver = ContextTargetResolver()

        let priceEl = VisibleElement(id: "ocr-1", type: .genericText, text: "Invoice Total: $450.00", bounds: ElementBounds(x: 50, y: 100, width: 200, height: 20), source: .ocr)
        let emailEl = VisibleElement(id: "ocr-2", type: .genericText, text: "Billing Contact: billing@acme.corp", bounds: ElementBounds(x: 50, y: 130, width: 250, height: 20), source: .ocr)

        let ocrContext = UnifiedContext(
            source: .ocr,
            applicationName: "TextEdit",
            elements: [priceEl, emailEl],
            largeTextRegions: []
        )

        // Price
        let priceRes = resolver.resolve(target: .semantic(role: "price", topic: nil), in: ocrContext)
        if case .success(_, let text) = priceRes {
            XCTAssertEqual(text, "$450.00")
        } else {
            XCTFail("Expected price extraction from OCR context")
        }

        // Email
        let emailRes = resolver.resolve(target: .semantic(role: "email", topic: nil), in: ocrContext)
        if case .success(_, let text) = emailRes {
            XCTAssertEqual(text, "billing@acme.corp")
        } else {
            XCTFail("Expected email extraction from OCR context")
        }
    }
}
