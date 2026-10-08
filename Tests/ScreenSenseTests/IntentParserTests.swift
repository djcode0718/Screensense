import XCTest
@testable import ScreenSenseCore

final class IntentParserTests: XCTestCase {
    var parser: GenericIntentParser!

    override func setUp() {
        super.setUp()
        parser = GenericIntentParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Wake Word & Paste Tests

    func testWakeWordStripping() {
        let r1 = parser.parse(transcript: "ScreenSense, paste")
        if case .paste = r1 {
            // Success
        } else {
            XCTFail("Expected paste intent after wake word")
        }

        let r2 = parser.parse(transcript: "Hey ScreenSense, copy the third paragraph")
        if case .copy(let intent) = r2 {
            if case .element(let type, let idx) = intent.target {
                XCTAssertEqual(type, .paragraph)
                XCTAssertEqual(idx, 3)
            } else {
                XCTFail("Expected .element target")
            }
        } else {
            XCTFail("Expected copy intent")
        }
    }

    // MARK: - Word Range Tests

    func testWordRangeParsing() {
        // "copy words 5 to 12 from the third paragraph"
        let r1 = parser.parse(transcript: "copy words 5 to 12 from the third paragraph")
        if case .copy(let intent) = r1 {
            if case .wordRange(let scope, let range) = intent.target {
                XCTAssertEqual(range.start, 5)
                XCTAssertEqual(range.end, 12)
                XCTAssertEqual(scope, .element(type: .paragraph, index: 3))
            } else {
                XCTFail("Expected .wordRange target, got \(intent.target)")
            }
        } else {
            XCTFail("Expected copy intent")
        }

        // "copy words 1 to 2 from the second heading"
        let r2 = parser.parse(transcript: "copy words 1 to 2 from the second heading")
        if case .copy(let intent) = r2 {
            if case .wordRange(let scope, let range) = intent.target {
                XCTAssertEqual(range.start, 1)
                XCTAssertEqual(range.end, 2)
                XCTAssertEqual(scope, .element(type: .heading, index: 2))
            } else {
                XCTFail("Expected .wordRange target")
            }
        } else {
            XCTFail("Expected copy intent")
        }

        // "copy from word 5 to word 12"
        let r3 = parser.parse(transcript: "copy from word 5 to word 12")
        if case .copy(let intent) = r3 {
            if case .wordRange(_, let range) = intent.target {
                XCTAssertEqual(range.start, 5)
                XCTAssertEqual(range.end, 12)
            } else {
                XCTFail("Expected .wordRange target")
            }
        } else {
            XCTFail("Expected copy intent")
        }
    }

    // MARK: - Text-to-Text Range Tests

    func testTextRangeParsing() {
        let r1 = parser.parse(transcript: "copy from Amazon to India")
        if case .copy(let intent) = r1 {
            if case .textRange(_, let range) = intent.target {
                XCTAssertEqual(range.startText, "amazon")
                XCTAssertEqual(range.endText, "india")
            } else {
                XCTFail("Expected .textRange target")
            }
        } else {
            XCTFail("Expected copy intent")
        }

        let r2 = parser.parse(transcript: "copy the text between Alpha and Omega")
        if case .copy(let intent) = r2 {
            if case .textRange(_, let range) = intent.target {
                XCTAssertEqual(range.startText, "alpha")
                XCTAssertEqual(range.endText, "omega")
            } else {
                XCTFail("Expected .textRange target")
            }
        } else {
            XCTFail("Expected copy intent")
        }
    }

    // MARK: - Semantic Roles Tests

    func testSemanticRoleParsing() {
        let queries: [(String, String, String?)] = [
            ("copy the company name", "company_name", nil),
            ("copy the job title", "job_title", nil),
            ("copy the phone number", "phone_number", nil),
            ("copy the page title", "title", nil),
            ("copy the email address", "email", nil),
            ("copy the price", "price", nil),
            ("copy the latest message", "latest_message", nil),
            ("copy the text about internship requirements", "text_about", "internship requirements"),
            ("copy the paragraph mentioning machine learning", "text_about", "machine learning")
        ]

        for (query, expectedRole, expectedTopic) in queries {
            let res = parser.parse(transcript: query)
            if case .copy(let intent) = res {
                if case .semantic(let role, let topic) = intent.target {
                    XCTAssertEqual(role, expectedRole, "Failed for '\(query)'")
                    XCTAssertEqual(topic, expectedTopic, "Failed topic for '\(query)'")
                } else {
                    XCTFail("Expected .semantic for '\(query)'")
                }
            } else {
                XCTFail("Expected copy intent for '\(query)'")
            }
        }
    }

    // MARK: - Spatial Relationship Tests

    func testSpatialRelationshipParsing() {
        let r1 = parser.parse(transcript: "copy the text below the title")
        if case .copy(let intent) = r1 {
            if case .spatial(let rel, let ref, _) = intent.target {
                XCTAssertEqual(rel, .below)
                XCTAssertEqual(ref, "title")
            } else {
                XCTFail("Expected .spatial target")
            }
        } else {
            XCTFail("Expected copy intent")
        }

        let r2 = parser.parse(transcript: "copy the text next to the apply button")
        if case .copy(let intent) = r2 {
            if case .spatial(let rel, let ref, _) = intent.target {
                XCTAssertEqual(rel, .nextTo)
                XCTAssertEqual(ref, "apply")
            } else {
                XCTFail("Expected .spatial target")
            }
        } else {
            XCTFail("Expected copy intent")
        }
    }
}
