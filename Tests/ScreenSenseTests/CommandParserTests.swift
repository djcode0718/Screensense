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
