import XCTest
@testable import ScreenSenseCore

final class ContextModelTests: XCTestCase {

    func testVisibleContextJSONSerialization() throws {
        let bounds = ElementBounds(x: 100, y: 250, width: 600, height: 80, documentX: 100, documentY: 1250)
        let element = VisibleElement(
            id: "el-1",
            type: .paragraph,
            text: "ScreenSense captures visible screen context.",
            bounds: bounds,
            visibilityPercentage: 0.95,
            confidence: 1.0,
            source: .dom,
            tag: "p",
            selector: "#intro"
        )

        let viewport = ViewportInfo(
            width: 1440,
            height: 900,
            scrollX: 0,
            scrollY: 1000,
            devicePixelRatio: 2.0,
            pageTitle: "ScreenSense Documentation",
            url: "https://example.com/docs"
        )

        let context = VisibleContext(
            id: "ctx-123",
            source: .dom,
            timestamp: Date(),
            viewport: viewport,
            elements: [element],
            screenshot: nil,
            metadata: ["test_key": "test_value"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(context)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(VisibleContext.self, from: data)

        XCTAssertEqual(decoded.id, "ctx-123")
        XCTAssertEqual(decoded.source, .dom)
        XCTAssertEqual(decoded.viewport.width, 1440)
        XCTAssertEqual(decoded.viewport.pageTitle, "ScreenSense Documentation")
        XCTAssertEqual(decoded.elements.count, 1)
        XCTAssertEqual(decoded.elements.first?.type, .paragraph)
        XCTAssertEqual(decoded.elements.first?.visibilityPercentage, 0.95)
        XCTAssertEqual(decoded.elements.first?.bounds.y, 250)
    }

    func testVisibleContextDateDecodingWithFractionalSeconds() throws {
        let json = """
        {
            "id": "ctx-frac-123",
            "source": "dom",
            "timestamp": "2026-10-08T15:21:40.123Z",
            "viewport": {
                "width": 1920,
                "height": 1080,
                "scrollX": 0,
                "scrollY": 0,
                "devicePixelRatio": 2.0,
                "pageTitle": "Example",
                "url": "https://example.com"
            },
            "elements": [
                {
                    "id": "el-1",
                    "type": "heading",
                    "text": "Heading Test",
                    "bounds": { "x": 10, "y": 20, "width": 100, "height": 30 },
                    "visibilityPercentage": 1.0,
                    "confidence": 1.0,
                    "source": "dom"
                }
            ],
            "metadata": {}
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let dateStr = try container.decode(String.self)
            let iso8601WithMillis = ISO8601DateFormatter()
            iso8601WithMillis.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601WithMillis.date(from: dateStr) {
                return date
            }
            let iso8601Standard = ISO8601DateFormatter()
            iso8601Standard.formatOptions = [.withInternetDateTime]
            if let date = iso8601Standard.date(from: dateStr) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected date string to be ISO8601-formatted"
            )
        }

        let data = Data(json.utf8)
        let decoded = try decoder.decode(VisibleContext.self, from: data)

        XCTAssertEqual(decoded.id, "ctx-frac-123")
        XCTAssertEqual(decoded.source, .dom)
        XCTAssertEqual(decoded.elements.count, 1)
        XCTAssertEqual(decoded.elements.first?.text, "Heading Test")
    }

    func testVisibleContextDateDecodingWithoutFractionalSeconds() throws {
        let json = """
        {
            "id": "ctx-std-123",
            "source": "dom",
            "timestamp": "2026-10-08T15:21:40Z",
            "viewport": {
                "width": 1920,
                "height": 1080,
                "scrollX": 0,
                "scrollY": 0,
                "devicePixelRatio": 2.0
            },
            "elements": [],
            "metadata": {}
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let dateStr = try container.decode(String.self)
            let iso8601WithMillis = ISO8601DateFormatter()
            iso8601WithMillis.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601WithMillis.date(from: dateStr) {
                return date
            }
            let iso8601Standard = ISO8601DateFormatter()
            iso8601Standard.formatOptions = [.withInternetDateTime]
            if let date = iso8601Standard.date(from: dateStr) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected date string to be ISO8601-formatted"
            )
        }

        let data = Data(json.utf8)
        let decoded = try decoder.decode(VisibleContext.self, from: data)

        XCTAssertEqual(decoded.id, "ctx-std-123")
        XCTAssertEqual(decoded.source, .dom)
        XCTAssertEqual(decoded.elements.count, 0)
    }

    func testSpatialOrderingPreservation() {
        // Create elements out of visual order
        let elBottom = VisibleElement(
            id: "bottom",
            type: .paragraph,
            text: "Paragraph 3 (Bottom)",
            bounds: ElementBounds(x: 50, y: 600, width: 500, height: 40)
        )
        let elTop = VisibleElement(
            id: "top",
            type: .heading,
            text: "Heading 1 (Top)",
            bounds: ElementBounds(x: 50, y: 100, width: 500, height: 30)
        )
        let elMiddle = VisibleElement(
            id: "middle",
            type: .paragraph,
            text: "Paragraph 2 (Middle)",
            bounds: ElementBounds(x: 50, y: 350, width: 500, height: 40)
        )

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1200, height: 800),
            elements: [elBottom, elTop, elMiddle]
        )

        let sorted = context.spatiallySortedElements
        XCTAssertEqual(sorted.count, 3)
        XCTAssertEqual(sorted[0].id, "top")
        XCTAssertEqual(sorted[1].id, "middle")
        XCTAssertEqual(sorted[2].id, "bottom")
    }

    func testElementsOfTypeFiltering() {
        let h1 = VisibleElement(id: "h1", type: .heading, text: "Title", bounds: ElementBounds(x: 0, y: 0, width: 100, height: 20))
        let p1 = VisibleElement(id: "p1", type: .paragraph, text: "Para 1", bounds: ElementBounds(x: 0, y: 30, width: 100, height: 20))
        let p2 = VisibleElement(id: "p2", type: .paragraph, text: "Para 2", bounds: ElementBounds(x: 0, y: 60, width: 100, height: 20))
        let btn = VisibleElement(id: "btn", type: .button, text: "Submit", bounds: ElementBounds(x: 0, y: 90, width: 100, height: 20))

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 800, height: 600),
            elements: [h1, p1, p2, btn]
        )

        let paragraphs = context.elements(ofType: .paragraph)
        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs.map { $0.id }, ["p1", "p2"])

        let headings = context.elements(ofType: .heading)
        XCTAssertEqual(headings.count, 1)
        XCTAssertEqual(headings.first?.id, "h1")
    }
}
