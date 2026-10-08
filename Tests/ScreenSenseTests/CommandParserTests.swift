import XCTest
@testable import ScreenSenseCore

final class CommandParserTests: XCTestCase {
    var parser: DeterministicCommandParser!

    override func setUp() {
        super.setUp()
        parser = DeterministicCommandParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    func testStringNormalization() {
        XCTAssertEqual(StringNormalizer.normalize("  Paste!  "), "paste")
        XCTAssertEqual(StringNormalizer.normalize("Please,   PASTE   HERE..."), "please paste here")
        XCTAssertEqual(StringNormalizer.normalize("“Paste”"), "paste")
        XCTAssertEqual(StringNormalizer.normalize(""), "")
    }

    func testPasteCommandParsing() {
        let exactPhrases = [
            "paste",
            "Paste",
            "PASTE",
            "  paste  ",
            "paste!",
            "paste.",
            "paste, please"
        ]

        for phrase in exactPhrases {
            let result = parser.parse(transcript: phrase)
            switch result {
            case .success(let command):
                XCTAssertEqual(command.actionType, .paste, "Expected .paste for '\(phrase)'")
            default:
                XCTFail("Failed to parse '\(phrase)' as paste command")
            }
        }
    }

    func testPasteVariationsParsing() {
        let variations = [
            "paste here",
            "Paste Here!",
            "please paste",
            "please paste here",
            "paste this",
            "paste it",
            "paste at cursor",
            "can you paste",
            "hey please paste",
            "screensense paste",
            "just paste"
        ]

        for phrase in variations {
            let result = parser.parse(transcript: phrase)
            switch result {
            case .success(let command):
                XCTAssertEqual(command.actionType, .paste, "Expected .paste for '\(phrase)'")
            default:
                XCTFail("Failed to parse variation '\(phrase)' as paste command")
            }
        }
    }

    func testCopyParagraphCommandParsing() {
        let exactPhrases = [
            "copy the paragraph",
            "Copy the paragraph",
            "COPY THE PARAGRAPH",
            "  copy the paragraph  ",
            "copy paragraph",
            "Copy Paragraph!",
            "please copy the paragraph",
            "please copy paragraph",
            "can you copy the paragraph",
            "copy this paragraph",
            "copy that paragraph",
            "copy the paragraph please",
            "copy paragraph please"
        ]

        for phrase in exactPhrases {
            let result = parser.parse(transcript: phrase)
            switch result {
            case .success(let command):
                XCTAssertEqual(command.actionType, .copy, "Expected .copy for '\(phrase)'")
                XCTAssertEqual(command.description, "Copy Paragraph")
            default:
                XCTFail("Failed to parse '\(phrase)' as copy paragraph command")
            }
        }
    }

    func testCopyIndexedParagraphCommandParsing() {
        let indexedCases: [(phrase: String, expectedIndex: Int)] = [
            ("copy the first paragraph", 1),
            ("Copy the first paragraph", 1),
            ("copy the 1st paragraph", 1),
            ("copy paragraph 1", 1),
            ("copy the second paragraph", 2),
            ("copy second paragraph", 2),
            ("copy the 2nd paragraph", 2),
            ("copy paragraph 2", 2),
            ("copy the third paragraph", 3),
            ("Copy the third paragraph", 3),
            ("copy third paragraph", 3),
            ("copy the 3rd paragraph", 3),
            ("copy paragraph 3", 3),
            ("please copy the third paragraph", 3),
            ("can you copy the 3rd paragraph", 3),
            ("copy the fourth paragraph", 4),
            ("copy paragraph 4", 4),
            ("copy the 4th paragraph", 4),
            ("copy the fifth paragraph", 5),
            ("copy paragraph 5", 5),
            ("copy the 5th paragraph", 5)
        ]

        for (phrase, expectedIndex) in indexedCases {
            let result = parser.parse(transcript: phrase)
            switch result {
            case .success(let command):
                XCTAssertEqual(command.actionType, .copy, "Expected .copy for '\(phrase)'")
                XCTAssertEqual(command.description, "Copy Paragraph #\(expectedIndex)", "Expected description 'Copy Paragraph #\(expectedIndex)' for '\(phrase)'")
            default:
                XCTFail("Failed to parse '\(phrase)' as indexed copy paragraph command")
            }
        }
    }

    func testCopyHeadingCommandParsing() {
        let genericPhrases = [
            "copy the heading",
            "copy heading",
            "Copy Heading!",
            "please copy the heading",
            "copy this heading",
            "copy that heading"
        ]

        for phrase in genericPhrases {
            let result = parser.parse(transcript: phrase)
            switch result {
            case .success(let command):
                XCTAssertEqual(command.actionType, .copy, "Expected .copy for '\(phrase)'")
                XCTAssertEqual(command.description, "Copy Heading")
            default:
                XCTFail("Failed to parse '\(phrase)' as copy heading command")
            }
        }

        let indexedPhrases: [(phrase: String, expectedIndex: Int)] = [
            ("copy the first heading", 1),
            ("copy first heading", 1),
            ("copy the 1st heading", 1),
            ("copy heading 1", 1),
            ("copy the second heading", 2),
            ("copy second heading", 2),
            ("copy heading 2", 2),
            ("copy the 2nd heading", 2),
            ("please copy the second heading", 2)
        ]

        for (phrase, expectedIndex) in indexedPhrases {
            let result = parser.parse(transcript: phrase)
            switch result {
            case .success(let command):
                XCTAssertEqual(command.actionType, .copy, "Expected .copy for '\(phrase)'")
                XCTAssertEqual(command.description, "Copy Heading #\(expectedIndex)")
            default:
                XCTFail("Failed to parse '\(phrase)' as indexed copy heading command")
            }
        }
    }

    func testCopyButtonCommandParsing() {
        let genericPhrases = [
            "copy the button",
            "copy button",
            "Copy Button!",
            "please copy the button",
            "can you copy the button"
        ]

        for phrase in genericPhrases {
            let result = parser.parse(transcript: phrase)
            switch result {
            case .success(let command):
                XCTAssertEqual(command.actionType, .copy, "Expected .copy for '\(phrase)'")
                XCTAssertEqual(command.description, "Copy Button")
            default:
                XCTFail("Failed to parse '\(phrase)' as copy button command")
            }
        }

        let indexedPhrases: [(phrase: String, expectedIndex: Int)] = [
            ("copy the first button", 1),
            ("copy first button", 1),
            ("copy button 1", 1),
            ("copy the second button", 2),
            ("copy second button", 2),
            ("copy button 2", 2),
            ("copy the 2nd button", 2),
            ("can you copy button 2", 2)
        ]

        for (phrase, expectedIndex) in indexedPhrases {
            let result = parser.parse(transcript: phrase)
            switch result {
            case .success(let command):
                XCTAssertEqual(command.actionType, .copy, "Expected .copy for '\(phrase)'")
                XCTAssertEqual(command.description, "Copy Button #\(expectedIndex)")
            default:
                XCTFail("Failed to parse '\(phrase)' as indexed copy button command")
            }
        }
    }

    func testCopyLinkCommandParsing() {
        let genericPhrases = [
            "copy the link",
            "copy link",
            "Copy Link!",
            "please copy the link"
        ]

        for phrase in genericPhrases {
            let result = parser.parse(transcript: phrase)
            switch result {
            case .success(let command):
                XCTAssertEqual(command.actionType, .copy, "Expected .copy for '\(phrase)'")
                XCTAssertEqual(command.description, "Copy Link")
            default:
                XCTFail("Failed to parse '\(phrase)' as copy link command")
            }
        }

        let indexedPhrases: [(phrase: String, expectedIndex: Int)] = [
            ("copy the first link", 1),
            ("copy first link", 1),
            ("copy the second link", 2),
            ("copy link 2", 2),
            ("copy the 2nd link", 2),
            ("copy the third link", 3),
            ("copy link 3", 3),
            ("copy the 3rd link", 3),
            ("please copy the third link", 3)
        ]

        for (phrase, expectedIndex) in indexedPhrases {
            let result = parser.parse(transcript: phrase)
            switch result {
            case .success(let command):
                XCTAssertEqual(command.actionType, .copy, "Expected .copy for '\(phrase)'")
                XCTAssertEqual(command.description, "Copy Link #\(expectedIndex)")
            default:
                XCTFail("Failed to parse '\(phrase)' as indexed copy link command")
            }
        }
    }

    func testEmptyTranscript() {
        let emptyCases = ["", "   ", "...", " , ! ? "]
        for empty in emptyCases {
            let result = parser.parse(transcript: empty)
            XCTAssertEqual(result, .empty, "Expected .empty for '\(empty)'")
        }
    }

    func testUnsupportedCommands() {
        let unsupportedPhrases = [
            "open safari",
            "click on the button",
            "scroll down",
            "hello world",
            "what is the time",
            "type some text"
        ]

        for phrase in unsupportedPhrases {
            let result = parser.parse(transcript: phrase)
            switch result {
            case .unsupported(let raw, _):
                XCTAssertEqual(raw, phrase)
            default:
                XCTFail("Expected .unsupported for '\(phrase)', got \(result)")
            }
        }
    }
}
