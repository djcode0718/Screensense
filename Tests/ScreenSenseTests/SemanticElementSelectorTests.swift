import XCTest
@testable import ScreenSenseCore

final class SemanticElementSelectorTests: XCTestCase {
    var selector: SemanticElementSelector!

    override func setUp() {
        super.setUp()
        selector = SemanticElementSelector()
    }

    override func tearDown() {
        selector = nil
        super.tearDown()
    }

    // MARK: - 1. Below Title / Heading Tests

    func testSelectNearestParagraphBelowTitle() {
        let title = VisibleElement(id: "h1", type: .heading, text: "ScreenSense Test Store", bounds: ElementBounds(x: 50, y: 50, width: 400, height: 40), tag: "h1")
        let introP = VisibleElement(id: "p1", type: .paragraph, text: "Product: Premium Wireless Headphones.", bounds: ElementBounds(x: 50, y: 100, width: 600, height: 30), tag: "p")
        let priceDiv = VisibleElement(id: "div1", type: .genericText, text: "Price: ₹2,499", bounds: ElementBounds(x: 50, y: 150, width: 200, height: 30), tag: "div")

        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [title, introP, priceDiv])

        let result = selector.select(intent: .below(reference: .title), in: context)

        switch result {
        case .success(let element, let text):
            XCTAssertEqual(element.id, "p1")
            XCTAssertEqual(text, "Product: Premium Wireless Headphones.")
        default:
            XCTFail("Expected .success, got \(result)")
        }
    }

    func testSelectTextUnderMatchingHeading() {
        let h1 = VisibleElement(id: "h1", type: .heading, text: "Store Overview", bounds: ElementBounds(x: 50, y: 50, width: 400, height: 40), tag: "h1")
        let p1 = VisibleElement(id: "p1", type: .paragraph, text: "Overview paragraph text.", bounds: ElementBounds(x: 50, y: 100, width: 600, height: 30), tag: "p")
        let h2 = VisibleElement(id: "h2", type: .heading, text: "Heading Two", bounds: ElementBounds(x: 50, y: 200, width: 400, height: 40), tag: "h2")
        let p2 = VisibleElement(id: "p2", type: .paragraph, text: "This is ScreenSense paragraph under Heading Two.", bounds: ElementBounds(x: 50, y: 250, width: 600, height: 30), tag: "p")

        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [h1, p1, h2, p2])

        let result = selector.select(intent: .below(reference: .heading(text: "Heading Two")), in: context)

        switch result {
        case .success(let element, let text):
            XCTAssertEqual(element.id, "p2")
            XCTAssertEqual(text, "This is ScreenSense paragraph under Heading Two.")
        default:
            XCTFail("Expected .success, got \(result)")
        }
    }

    func testSelectTextBelowHeadingNotFound() {
        let h1 = VisibleElement(id: "h1", type: .heading, text: "Only Heading", bounds: ElementBounds(x: 50, y: 50, width: 400, height: 40), tag: "h1")
        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [h1])

        let result = selector.select(intent: .below(reference: .title), in: context)

        switch result {
        case .notFound(let reason):
            XCTAssertTrue(reason.contains("No visible text found below"))
        default:
            XCTFail("Expected .notFound, got \(result)")
        }
    }

    // MARK: - 2. Next To Button Tests

    func testSelectTextNextToButton() {
        let button = VisibleElement(id: "btn-apply", type: .button, text: "Apply Coupon", bounds: ElementBounds(x: 50, y: 200, width: 140, height: 40), tag: "button")
        let adjacentText = VisibleElement(id: "note", type: .genericText, text: "Discount available for students.", bounds: ElementBounds(x: 200, y: 205, width: 250, height: 30), tag: "span")
        let distantText = VisibleElement(id: "p-other", type: .paragraph, text: "Unrelated text far below.", bounds: ElementBounds(x: 50, y: 400, width: 500, height: 30), tag: "p")

        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [button, adjacentText, distantText])

        let result = selector.select(intent: .nextTo(reference: .button(text: "Apply")), in: context)

        switch result {
        case .success(let element, let text):
            XCTAssertEqual(element.id, "note")
            XCTAssertEqual(text, "Discount available for students.")
        default:
            XCTFail("Expected .success, got \(result)")
        }
    }

    func testSelectTextNextToButtonNotFound() {
        let button = VisibleElement(id: "btn-submit", type: .button, text: "Submit", bounds: ElementBounds(x: 50, y: 200, width: 140, height: 40), tag: "button")
        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [button])

        let result = selector.select(intent: .nextTo(reference: .button(text: "Submit")), in: context)

        switch result {
        case .notFound(let reason):
            XCTAssertTrue(reason.contains("No visible text found next to button"))
        default:
            XCTFail("Expected .notFound, got \(result)")
        }
    }

    // MARK: - 3. Email Extraction Tests

    func testSelectUniqueEmailAddress() {
        let title = VisibleElement(id: "h1", type: .heading, text: "Support Page", bounds: ElementBounds(x: 50, y: 50, width: 300, height: 30), tag: "h1")
        let emailEl = VisibleElement(id: "p-email", type: .paragraph, text: "Please contact support@screensense.test for help.", bounds: ElementBounds(x: 50, y: 100, width: 400, height: 30), tag: "p")

        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [title, emailEl])

        let result = selector.select(intent: .email, in: context)

        switch result {
        case .success(_, let extractedText):
            XCTAssertEqual(extractedText, "support@screensense.test")
        default:
            XCTFail("Expected .success with extracted email, got \(result)")
        }
    }

    func testSelectEmailAmbiguityWhenMultipleEmailsExist() {
        let e1 = VisibleElement(id: "p1", type: .paragraph, text: "Sales: sales@screensense.test", bounds: ElementBounds(x: 50, y: 50, width: 300, height: 30), tag: "p")
        let e2 = VisibleElement(id: "p2", type: .paragraph, text: "Support: help@screensense.test", bounds: ElementBounds(x: 50, y: 100, width: 300, height: 30), tag: "p")

        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [e1, e2])

        let result = selector.select(intent: .email, in: context)

        switch result {
        case .ambiguous(let reason, let candidates):
            XCTAssertTrue(reason.contains("Multiple email addresses are visible (2)"))
            XCTAssertEqual(candidates.count, 2)
        default:
            XCTFail("Expected .ambiguous, got \(result)")
        }
    }

    func testSelectEmailNotFound() {
        let p1 = VisibleElement(id: "p1", type: .paragraph, text: "No contact info here.", bounds: ElementBounds(x: 50, y: 50, width: 300, height: 30), tag: "p")
        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [p1])

        let result = selector.select(intent: .email, in: context)

        switch result {
        case .notFound(let reason):
            XCTAssertEqual(reason, "No visible email address found.")
        default:
            XCTFail("Expected .notFound, got \(result)")
        }
    }

    // MARK: - 4. Price Extraction Tests

    func testSelectUniquePriceRupee() {
        let priceEl = VisibleElement(id: "p-price", type: .genericText, text: "Price: ₹2,499", bounds: ElementBounds(x: 50, y: 50, width: 200, height: 30), tag: "div")
        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [priceEl])

        let result = selector.select(intent: .price, in: context)

        switch result {
        case .success(_, let extractedText):
            XCTAssertEqual(extractedText, "₹2,499")
        default:
            XCTFail("Expected .success with extracted price, got \(result)")
        }
    }

    func testSelectUniquePriceDollar() {
        let priceEl = VisibleElement(id: "p-price", type: .paragraph, text: "Total Amount: $29.99 including taxes", bounds: ElementBounds(x: 50, y: 50, width: 300, height: 30), tag: "p")
        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [priceEl])

        let result = selector.select(intent: .price, in: context)

        switch result {
        case .success(_, let extractedText):
            XCTAssertEqual(extractedText, "$29.99")
        default:
            XCTFail("Expected .success with extracted price, got \(result)")
        }
    }

    func testSelectPriceAmbiguityWhenMultiplePricesExist() {
        let p1 = VisibleElement(id: "p1", type: .genericText, text: "Base Price: ₹2,499", bounds: ElementBounds(x: 50, y: 50, width: 200, height: 30), tag: "div")
        let p2 = VisibleElement(id: "p2", type: .genericText, text: "Special Bundle: ₹3,499", bounds: ElementBounds(x: 50, y: 100, width: 200, height: 30), tag: "div")

        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [p1, p2])

        let result = selector.select(intent: .price, in: context)

        switch result {
        case .ambiguous(let reason, let candidates):
            XCTAssertTrue(reason.contains("Multiple prices are visible (2)"))
            XCTAssertEqual(candidates.count, 2)
        default:
            XCTFail("Expected .ambiguous, got \(result)")
        }
    }

    func testSelectPriceNotFound() {
        let p1 = VisibleElement(id: "p1", type: .paragraph, text: "Free open source software.", bounds: ElementBounds(x: 50, y: 50, width: 300, height: 30), tag: "p")
        let context = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [p1])

        let result = selector.select(intent: .price, in: context)

        switch result {
        case .notFound(let reason):
            XCTAssertEqual(reason, "No visible price found.")
        default:
            XCTFail("Expected .notFound, got \(result)")
        }
    }
}
