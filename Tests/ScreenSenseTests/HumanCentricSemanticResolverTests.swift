import XCTest
@testable import ScreenSenseCore

final class HumanCentricSemanticResolverTests: XCTestCase {
    var resolver: ContextTargetResolver!
    var intentParser: GenericIntentParser!

    override func setUp() {
        super.setUp()
        resolver = ContextTargetResolver()
        intentParser = GenericIntentParser()
    }

    override func tearDown() {
        resolver = nil
        intentParser = nil
        super.tearDown()
    }

    // Fixture simulating Wikipedia: Quantum computing top viewport
    private func createWikipediaTopFixture() -> UnifiedContext {
        let navTalk = VisibleElement(id: "nav-talk", type: .link, text: "Talk", bounds: ElementBounds(x: 200, y: 120, width: 40, height: 20), tag: "a")
        let navArticle = VisibleElement(id: "nav-article", type: .link, text: "Article", bounds: ElementBounds(x: 150, y: 120, width: 45, height: 20), tag: "a")
        let navTools = VisibleElement(id: "nav-tools", type: .button, text: "Tools", bounds: ElementBounds(x: 800, y: 120, width: 50, height: 20), tag: "button")
        let wikiTagline = VisibleElement(id: "tagline", type: .genericText, text: "From Wikipedia, the free encyclopedia", bounds: ElementBounds(x: 150, y: 145, width: 250, height: 16), tag: "div")

        let h1Title = VisibleElement(id: "firstHeading", type: .heading, text: "Quantum computing", bounds: ElementBounds(x: 150, y: 80, width: 400, height: 35), tag: "h1")
        
        let pIntro = VisibleElement(
            id: "mw-intro-p",
            type: .paragraph,
            text: "A quantum computer is a computer that takes advantage of quantum mechanical phenomena.",
            bounds: ElementBounds(x: 150, y: 170, width: 650, height: 60),
            tag: "p"
        )

        let pSecond = VisibleElement(
            id: "mw-second-p",
            type: .paragraph,
            text: "Quantum information science includes quantum computing, quantum cryptography, and quantum communication.",
            bounds: ElementBounds(x: 150, y: 240, width: 650, height: 60),
            tag: "p"
        )

        return UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: WindowInfo(title: "Quantum computing - Wikipedia", appName: "Google Chrome"),
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 0, pageTitle: "Quantum computing - Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
            elements: [h1Title, navArticle, navTalk, navTools, wikiTagline, pIntro, pSecond]
        )
    }

    // Fixture simulating Wikipedia scrolled down to "History" section
    private func createWikipediaScrolledFixture() -> UnifiedContext {
        let h2History = VisibleElement(id: "h2-history", type: .heading, text: "History", bounds: ElementBounds(x: 150, y: 40, width: 200, height: 30), tag: "h2")
        let editLink = VisibleElement(id: "edit-1", type: .link, text: "[edit]", bounds: ElementBounds(x: 360, y: 45, width: 35, height: 18), tag: "a")
        
        let pHistory = VisibleElement(
            id: "p-history-1",
            type: .paragraph,
            text: "The field of quantum computing began in the 1980s when Paul Benioff proposed a quantum mechanical model of the Turing machine.",
            bounds: ElementBounds(x: 150, y: 80, width: 650, height: 60),
            tag: "p"
        )

        return UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: WindowInfo(title: "Quantum computing - Wikipedia", appName: "Google Chrome"),
            viewport: ViewportInfo(width: 1440, height: 900, scrollX: 0, scrollY: 2200, pageTitle: "Quantum computing - Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
            elements: [h2History, editLink, pHistory]
        )
    }

    // 1. "Copy the title" returns page title both at top and when scrolled down
    func testCopyTitleAtTopAndScrolledPositions() {
        let topContext = createWikipediaTopFixture()
        let scrolledContext = createWikipediaScrolledFixture()

        let intent = intentParser.parse(transcript: "copy the title")
        guard case .copy(let copyIntent) = intent else {
            return XCTFail("Expected copy intent for 'copy the title'")
        }

        // At Top
        let resTop = resolver.resolve(target: copyIntent.target, in: topContext)
        if case .success(_, let text) = resTop {
            XCTAssertEqual(text, "Quantum computing - Wikipedia")
        } else {
            XCTFail("Expected title resolution at top")
        }

        // When Scrolled (should NOT return "History")
        let resScrolled = resolver.resolve(target: copyIntent.target, in: scrolledContext)
        if case .success(_, let text) = resScrolled {
            XCTAssertEqual(text, "Quantum computing - Wikipedia")
            XCTAssertNotEqual(text, "History", "Scrolling must NOT replace page title with section heading")
        } else {
            XCTFail("Expected page title resolution when scrolled")
        }
    }

    // 2. "Copy the first paragraph" returns introductory text, ignoring "Talk", "Tools", etc.
    func testCopyFirstParagraphIgnoresNavAndBoilerplate() {
        let context = createWikipediaTopFixture()
        let intent = intentParser.parse(transcript: "copy the first paragraph")
        guard case .copy(let copyIntent) = intent else {
            return XCTFail("Expected copy intent for 'copy the first paragraph'")
        }

        let res = resolver.resolve(target: copyIntent.target, in: context)
        if case .success(let el, let text) = res {
            XCTAssertEqual(el?.id, "mw-intro-p")
            XCTAssertEqual(text, "A quantum computer is a computer that takes advantage of quantum mechanical phenomena.")
        } else {
            XCTFail("Expected first paragraph resolution")
        }
    }

    // 3. "Copy the text below the title" returns meaningful introductory paragraph, NOT "Talk"
    func testCopyTextBelowTitleSelectsIntroContentNotTalk() {
        let context = createWikipediaTopFixture()
        let intent = intentParser.parse(transcript: "copy the text below the title")
        guard case .copy(let copyIntent) = intent else {
            return XCTFail("Expected copy intent for 'copy the text below the title'")
        }

        let res = resolver.resolve(target: copyIntent.target, in: context)
        if case .success(let el, let text) = res {
            XCTAssertNotEqual(text, "Talk", "Must not select navigation tab 'Talk'")
            XCTAssertNotEqual(text, "Article", "Must not select navigation tab 'Article'")
            XCTAssertEqual(el?.id, "mw-intro-p")
            XCTAssertEqual(text, "A quantum computer is a computer that takes advantage of quantum mechanical phenomena.")
        } else {
            XCTFail("Expected meaningful text below title resolution")
        }
    }

    // 4. Topic query "Copy the text about quantum computer" ranks candidates and picks best substantive region
    func testTopicQuerySelectsSubstantiveContentOverShortLink() {
        let linkMention = VisibleElement(id: "link-sim", type: .link, text: "Quantum computer simulator", bounds: ElementBounds(x: 150, y: 400, width: 180, height: 18))
        let divParagraph = VisibleElement(
            id: "article-block",
            type: .genericText,
            text: "A quantum computer utilizes quantum superposition and entanglement to perform complex state transformations.",
            bounds: ElementBounds(x: 150, y: 150, width: 600, height: 50),
            tag: "div"
        )

        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [linkMention, divParagraph]
        )

        let intent = intentParser.parse(transcript: "copy the text about quantum computer")
        guard case .copy(let copyIntent) = intent else {
            return XCTFail("Expected copy intent for 'copy the text about quantum computer'")
        }

        let res = resolver.resolve(target: copyIntent.target, in: context)
        if case .success(let el, let text) = res {
            XCTAssertEqual(el?.id, "article-block")
            XCTAssertTrue(text.contains("A quantum computer utilizes quantum superposition"))
        } else {
            XCTFail("Expected substantive paragraph selection for topic query")
        }
    }

    // 5. "Copy the paragraph about quantum information" matches div/section content seamlessly
    func testCopyParagraphAboutTopicMatchesRegardlessOfHTMLTag() {
        let sectionText = VisibleElement(
            id: "section-text",
            type: .genericText,
            text: "Quantum information science encompasses theoretical and experimental studies of qubit states.",
            bounds: ElementBounds(x: 150, y: 200, width: 600, height: 50),
            tag: "section"
        )

        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [sectionText]
        )

        let intent = intentParser.parse(transcript: "copy the paragraph about quantum information")
        guard case .copy(let copyIntent) = intent else {
            return XCTFail("Expected copy intent")
        }

        let res = resolver.resolve(target: copyIntent.target, in: context)
        if case .success(let el, let text) = res {
            XCTAssertEqual(el?.id, "section-text")
            XCTAssertEqual(text, "Quantum information science encompasses theoretical and experimental studies of qubit states.")
        } else {
            XCTFail("Expected paragraph topic match on section element")
        }
    }

    // 6. Generic natural language forms for topic extraction
    func testNaturalLanguageTopicVariations() {
        let phrases = [
            ("copy the text about quantum information", "quantum information"),
            ("copy the paragraph about quantum computers", "quantum computers"),
            ("copy the section about quantum information", "quantum information"),
            ("copy the paragraph discussing quantum algorithms", "quantum algorithms"),
            ("copy the text regarding quantum supremacy", "quantum supremacy"),
            ("copy the article on error correction", "error correction"),
            ("copy the text related to cryptography", "cryptography")
        ]

        for (phrase, expectedTopic) in phrases {
            let res = intentParser.parse(transcript: phrase)
            if case .copy(let copyIntent) = res {
                if case .semantic(let role, let topic) = copyIntent.target {
                    XCTAssertEqual(role, "text_about", "Failed role for '\(phrase)'")
                    XCTAssertEqual(topic, expectedTopic, "Failed topic for '\(phrase)'")
                } else {
                    XCTFail("Expected .semantic for '\(phrase)'")
                }
            } else {
                XCTFail("Expected copy intent for '\(phrase)'")
            }
        }
    }
}
