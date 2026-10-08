import Foundation

/// Protocol for parsing speech into structured user intents
public protocol IntentParserProtocol: Sendable {
    func parse(transcript: String) -> StructuredUserIntent
}

/// Generic, extensible intent parser supporting deterministic fast-path and semantic extraction
public struct GenericIntentParser: IntentParserProtocol, Sendable {
    public init() {}

    public func parse(transcript: String) -> StructuredUserIntent {
        let normalized = StringNormalizer.normalize(transcript)

        ScreenSenseLogger.parser.debug("[INTENT PARSER] Raw: '\(transcript, privacy: .public)', Normalized: '\(normalized, privacy: .public)'")

        if normalized.isEmpty {
            return .empty
        }

        // Clean wake-words and filler words: "screensense", "hey screensense", "please", "can you"
        let words = normalized.components(separatedBy: " ").filter { !$0.isEmpty }
        let cleanedWords = cleanWords(from: words)
        let cleanedNormalized = cleanedWords.joined(separator: " ")

        if cleanedWords.isEmpty {
            return .empty
        }

        // 1. Check for Paste Action
        if isPasteIntent(cleanedNormalized, words: cleanedWords) {
            return .paste(PasteIntent(rawTranscript: transcript, normalizedTranscript: cleanedNormalized))
        }

        // 2. Check for Selection Context Copy: "copy the selected text", "copy my selection", "copy the paragraph I selected"
        if let selectionIntent = parseSelectionIntent(cleanedWords, raw: transcript, norm: cleanedNormalized) {
            return .copy(selectionIntent)
        }

        // 3. Check for Pointer Context Copy: "copy the text under my cursor", "copy the paragraph under my cursor", "copy what I'm pointing at"
        if let pointerIntent = parsePointerIntent(cleanedWords, raw: transcript, norm: cleanedNormalized) {
            return .copy(pointerIntent)
        }

        // 4. Check for Word Range Copy: "copy words 5 to 12 from the third paragraph"
        if let wordRangeIntent = parseWordRangeIntent(cleanedWords, raw: transcript, norm: cleanedNormalized) {
            return .copy(wordRangeIntent)
        }

        // 5. Check for Text-to-Text Range Copy: "copy from Amazon to India", "copy between X and Y"
        if let textRangeIntent = parseTextRangeIntent(cleanedWords, raw: transcript, norm: cleanedNormalized) {
            return .copy(textRangeIntent)
        }

        // 6. Check for Spatial Relationship Copy: "copy the text below the title", "copy text next to apply button"
        if let spatialIntent = parseSpatialIntent(cleanedWords, raw: transcript, norm: cleanedNormalized) {
            return .copy(spatialIntent)
        }

        // 7. Check for Semantic Entities: "copy the company name", "copy the price", "copy email", "copy job title"
        if let semanticIntent = parseSemanticEntityIntent(cleanedWords, raw: transcript, norm: cleanedNormalized) {
            return .copy(semanticIntent)
        }

        // 8. Check for Explicit Element Copy: "copy the third paragraph", "copy heading 2", "copy button 1"
        if let elementIntent = parseExplicitElementIntent(cleanedWords, raw: transcript, norm: cleanedNormalized) {
            return .copy(elementIntent)
        }

        return .unsupported(
            transcript: transcript,
            reason: "Command not recognized: \"\(transcript)\""
        )
    }

    // MARK: - Word Cleaning & Wake Words

    private static let fillerWords: Set<String> = ["please", "hey", "can", "you", "just", "screensense", "now", "would", "could", "will", "do"]

    private func cleanWords(from words: [String]) -> [String] {
        var w = stripWakeWords(from: words)
        while !w.isEmpty && Self.fillerWords.contains(w[0]) {
            w.removeFirst()
        }
        while !w.isEmpty && Self.fillerWords.contains(w[w.count - 1]) {
            w.removeLast()
        }
        return w
    }

    private func stripWakeWords(from words: [String]) -> [String] {
        var w = words
        if w.count >= 2 && w[0] == "hey" && w[1] == "screensense" {
            w = Array(w.dropFirst(2))
        } else if w.count >= 1 && w[0] == "screensense" {
            w = Array(w.dropFirst(1))
        }
        return w
    }

    // MARK: - Paste Intent

    private func isPasteIntent(_ normalized: String, words: [String]) -> Bool {
        let directMatches: Set<String> = [
            "paste", "paste here", "please paste", "please paste here",
            "paste this", "paste it", "paste at cursor", "can you paste", "just paste"
        ]
        if directMatches.contains(normalized) { return true }

        let filler: Set<String> = ["please", "hey", "can", "you", "just", "now", "would", "could"]
        let stripped = words.filter { !filler.contains($0) }
        return stripped == ["paste"] || stripped == ["paste", "here"] || stripped == ["paste", "this"] || stripped == ["paste", "it"]
    }

    // MARK: - Word Range Parser

    private func parseWordRangeIntent(_ words: [String], raw: String, norm: String) -> CopyIntent? {
        // e.g. ["copy", "words", "5", "to", "12", "from", "the", "third", "paragraph"]
        // e.g. ["copy", "words", "1", "to", "2", "from", "the", "second", "heading"]
        // e.g. ["copy", "from", "word", "5", "to", "word", "12"]
        guard words.first == "copy" else { return nil }

        let tokens = Array(words.dropFirst())
        guard tokens.count >= 4 else { return nil }

        var startWord: Int?
        var endWord: Int?
        var scopeTokens: [String] = []

        // Pattern: "words <start> to <end> [from ...]"
        if tokens[0] == "words" || tokens[0] == "word" {
            if let s = Int(tokens[1]), tokens.count >= 4 && tokens[2] == "to", let e = Int(tokens[3]) {
                startWord = s
                endWord = e
                if tokens.count > 4 && (tokens[4] == "from" || tokens[4] == "in" || tokens[4] == "of") {
                    scopeTokens = Array(tokens.dropFirst(5))
                }
            }
        } else if tokens[0] == "from" && tokens[1] == "word" {
            // Pattern: "from word <start> to word <end>"
            if let s = Int(tokens[2]), tokens.count >= 6 && tokens[3] == "to" && tokens[4] == "word", let e = Int(tokens[5]) {
                startWord = s
                endWord = e
                if tokens.count > 6 && (tokens[6] == "from" || tokens[6] == "in") {
                    scopeTokens = Array(tokens.dropFirst(7))
                }
            }
        }

        if let s = startWord, let e = endWord {
            var scope: TargetScope? = nil
            if !scopeTokens.isEmpty {
                scope = parseScope(from: scopeTokens)
            }
            let target = IntentTarget.wordRange(scope: scope, range: WordRange(start: s, end: e))
            return CopyIntent(target: target, rawTranscript: raw, normalizedTranscript: norm)
        }

        return nil
    }

    // MARK: - Text-to-Text Range Parser

    private func parseTextRangeIntent(_ words: [String], raw: String, norm: String) -> CopyIntent? {
        // e.g. ["copy", "from", "amazon", "to", "india"]
        // e.g. ["copy", "the", "text", "between", "amazon", "and", "india"]
        guard words.first == "copy" else { return nil }

        let tokens = Array(words.dropFirst())

        // Pattern 1: "copy from <start> to <end>"
        if tokens.count >= 4 && tokens[0] == "from" {
            if let toIndex = tokens.firstIndex(where: { $0 == "to" }), toIndex > 1 && toIndex < tokens.count - 1 {
                let startText = tokens[1..<toIndex].joined(separator: " ")
                let endText = tokens[(toIndex + 1)...].joined(separator: " ")
                let target = IntentTarget.textRange(scope: nil, range: TextRange(startText: startText, endText: endText))
                return CopyIntent(target: target, rawTranscript: raw, normalizedTranscript: norm)
            }
        }

        // Pattern 2: "copy [the text] between <start> and <end>"
        var scanTokens = tokens
        let articles: Set<String> = ["the", "this", "that"]
        if scanTokens.count >= 2 && articles.contains(scanTokens[0]) && scanTokens[1] == "text" {
            scanTokens = Array(scanTokens.dropFirst(2))
        } else if scanTokens.count >= 1 && scanTokens[0] == "text" {
            scanTokens = Array(scanTokens.dropFirst(1))
        }

        if scanTokens.count >= 4 && scanTokens[0] == "between" {
            if let andIndex = scanTokens.firstIndex(where: { $0 == "and" }), andIndex > 1 && andIndex < scanTokens.count - 1 {
                let startText = scanTokens[1..<andIndex].joined(separator: " ")
                let endText = scanTokens[(andIndex + 1)...].joined(separator: " ")
                let target = IntentTarget.textRange(scope: nil, range: TextRange(startText: startText, endText: endText))
                return CopyIntent(target: target, rawTranscript: raw, normalizedTranscript: norm)
            }
        }

        return nil
    }

    // MARK: - Spatial Relationship Parser

    private func parseSpatialIntent(_ words: [String], raw: String, norm: String) -> CopyIntent? {
        guard words.first == "copy" else { return nil }
        let tokens = Array(words.dropFirst())
        let articles: Set<String> = ["the", "this", "that", "a", "an"]

        var scanTokens = tokens
        if scanTokens.count >= 2 && articles.contains(scanTokens[0]) && scanTokens[1] == "text" {
            scanTokens = Array(scanTokens.dropFirst(2))
        } else if scanTokens.count >= 1 && scanTokens[0] == "text" {
            scanTokens = Array(scanTokens.dropFirst(1))
        }

        // Below / Under
        if scanTokens.count >= 2 && (scanTokens[0] == "below" || scanTokens[0] == "under") {
            let rel: SpatialRelationship = scanTokens[0] == "below" ? .below : .under
            var refTokens = Array(scanTokens.dropFirst(1))
            if let first = refTokens.first, articles.contains(first) {
                refTokens = Array(refTokens.dropFirst(1))
            }
            let refText = refTokens.joined(separator: " ")
            let target = IntentTarget.spatial(relationship: rel, referenceText: refText, referenceType: .heading)
            return CopyIntent(target: target, rawTranscript: raw, normalizedTranscript: norm)
        }

        // Next to
        if scanTokens.count >= 3 && scanTokens[0] == "next" && scanTokens[1] == "to" {
            var refTokens = Array(scanTokens.dropFirst(2))
            if let first = refTokens.first, articles.contains(first) {
                refTokens = Array(refTokens.dropFirst(1))
            }
            if refTokens.last == "button" {
                refTokens = Array(refTokens.dropLast(1))
            }
            let refText = refTokens.joined(separator: " ")
            let target = IntentTarget.spatial(relationship: .nextTo, referenceText: refText, referenceType: .button)
            return CopyIntent(target: target, rawTranscript: raw, normalizedTranscript: norm)
        }

        return nil
    }

    // MARK: - Semantic Entity Parser

    private func parseSemanticEntityIntent(_ words: [String], raw: String, norm: String) -> CopyIntent? {
        guard words.first == "copy" else { return nil }
        let tokens = Array(words.dropFirst())
        let articles: Set<String> = ["the", "this", "that", "a", "an"]

        var cleanTokens = tokens
        if let first = cleanTokens.first, articles.contains(first) {
            cleanTokens = Array(cleanTokens.dropFirst(1))
        }

        let phrase = cleanTokens.joined(separator: " ")

        // Email
        if phrase == "email" || phrase == "email address" {
            return CopyIntent(target: .semantic(role: "email", topic: nil), rawTranscript: raw, normalizedTranscript: norm)
        }

        // Price
        if phrase == "price" || phrase == "total price" {
            return CopyIntent(target: .semantic(role: "price", topic: nil), rawTranscript: raw, normalizedTranscript: norm)
        }

        // Phone
        if phrase == "phone number" || phrase == "phone" || phrase == "contact number" {
            return CopyIntent(target: .semantic(role: "phone_number", topic: nil), rawTranscript: raw, normalizedTranscript: norm)
        }

        // Company Name
        if phrase == "company name" || phrase == "company" || phrase == "company that posted this job" {
            return CopyIntent(target: .semantic(role: "company_name", topic: nil), rawTranscript: raw, normalizedTranscript: norm)
        }

        // Job Title
        if phrase == "job title" || phrase == "job role" || phrase == "position" {
            return CopyIntent(target: .semantic(role: "job_title", topic: nil), rawTranscript: raw, normalizedTranscript: norm)
        }

        // Page Title / Article Title / Headline
        if phrase == "title" || phrase == "page title" || phrase == "main title" ||
           phrase == "article title" || phrase == "document title" || phrase == "headline" ||
           phrase == "title of the page" || phrase == "title of the article" || phrase == "page header" {
            return CopyIntent(target: .semantic(role: "title", topic: nil), rawTranscript: raw, normalizedTranscript: norm)
        }

        // Topic/Content: e.g. "paragraph about X", "text discussing Y", "section on Z", "text regarding W", "paragraph explaining K"
        let topicTargetNouns: Set<String> = ["text", "paragraph", "section", "part", "information", "content", "article", "heading", "words", "details", "passage"]
        let topicPrepositions: Set<String> = ["about", "discussing", "mentioning", "on", "regarding", "explaining", "describing", "covering"]

        if cleanTokens.count >= 3 && topicTargetNouns.contains(cleanTokens[0]) {
            if topicPrepositions.contains(cleanTokens[1]) {
                let topic = cleanTokens.dropFirst(2).joined(separator: " ")
                if !topic.isEmpty {
                    return CopyIntent(target: .semantic(role: "text_about", topic: topic), rawTranscript: raw, normalizedTranscript: norm)
                }
            } else if cleanTokens.count >= 4 && cleanTokens[1] == "related" && cleanTokens[2] == "to" {
                let topic = cleanTokens.dropFirst(3).joined(separator: " ")
                if !topic.isEmpty {
                    return CopyIntent(target: .semantic(role: "text_about", topic: topic), rawTranscript: raw, normalizedTranscript: norm)
                }
            }
        }
        if cleanTokens.count >= 2 && (cleanTokens[0] == "about" || cleanTokens[0] == "discussing" || cleanTokens[0] == "regarding") {
            let topic = cleanTokens.dropFirst(1).joined(separator: " ")
            if !topic.isEmpty {
                return CopyIntent(target: .semantic(role: "text_about", topic: topic), rawTranscript: raw, normalizedTranscript: norm)
            }
        }

        // Latest Message
        if phrase == "latest message" || phrase == "last message" {
            return CopyIntent(target: .semantic(role: "latest_message", topic: nil), rawTranscript: raw, normalizedTranscript: norm)
        }

        return nil
    }

    // MARK: - Explicit Element Parser

    private func parseExplicitElementIntent(_ words: [String], raw: String, norm: String) -> CopyIntent? {
        guard words.first == "copy" else { return nil }
        let tokens = Array(words.dropFirst())
        guard !tokens.isEmpty else { return nil }

        let articles: Set<String> = ["the", "this", "that", "a", "an"]
        let ordinalMap: [String: Int] = [
            "first": 1, "1st": 1, "one": 1, "1": 1,
            "second": 2, "2nd": 2, "two": 2, "2": 2,
            "third": 3, "3rd": 3, "three": 3, "3": 3,
            "fourth": 4, "4th": 4, "four": 4, "4": 4,
            "fifth": 5, "5th": 5, "five": 5, "5": 5,
            "sixth": 6, "6th": 6, "six": 6, "6": 6,
            "seventh": 7, "7th": 7, "seven": 7, "7": 7,
            "eighth": 8, "8th": 8, "eight": 8, "8": 8,
            "ninth": 9, "9th": 9, "nine": 9, "9": 9,
            "tenth": 10, "10th": 10, "ten": 10, "10": 10
        ]
        let nounMap: [String: ElementType] = [
            "heading": .heading, "headings": .heading, "header": .heading, "title": .heading,
            "button": .button, "buttons": .button,
            "link": .link, "links": .link,
            "paragraph": .paragraph, "paragraphs": .paragraph,
            "text": .paragraph, "texts": .paragraph,
            "section": .paragraph, "sections": .paragraph,
            "article": .paragraph, "articles": .paragraph,
            "content": .paragraph, "contents": .paragraph
        ]

        // 1. [NOUN]
        if tokens.count == 1, let t = nounMap[tokens[0]] {
            return CopyIntent(target: .element(type: t, index: nil), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 2. [ARTICLE, NOUN]
        if tokens.count == 2, articles.contains(tokens[0]), let t = nounMap[tokens[1]] {
            return CopyIntent(target: .element(type: t, index: nil), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 3. [ORDINAL, NOUN]
        if tokens.count == 2, let idx = ordinalMap[tokens[0]], let t = nounMap[tokens[1]] {
            return CopyIntent(target: .element(type: t, index: idx), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 4. [ARTICLE, ORDINAL, NOUN]
        if tokens.count == 3, articles.contains(tokens[0]), let idx = ordinalMap[tokens[1]], let t = nounMap[tokens[2]] {
            return CopyIntent(target: .element(type: t, index: idx), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 5. [NOUN, ORDINAL]
        if tokens.count == 2, let t = nounMap[tokens[0]], let idx = ordinalMap[tokens[1]] {
            return CopyIntent(target: .element(type: t, index: idx), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 6. [ARTICLE, NOUN, ORDINAL]
        if tokens.count == 3, articles.contains(tokens[0]), let t = nounMap[tokens[1]], let idx = ordinalMap[tokens[2]] {
            return CopyIntent(target: .element(type: t, index: idx), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 7. [NOUN, "number", ORDINAL] -> e.g. ["heading", "number", "2"]
        if tokens.count == 3, tokens[1] == "number", let t = nounMap[tokens[0]], let idx = ordinalMap[tokens[2]] {
            return CopyIntent(target: .element(type: t, index: idx), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 8. [ARTICLE, NOUN, "number", ORDINAL] -> e.g. ["the", "link", "number", "3"]
        if tokens.count == 4, articles.contains(tokens[0]), tokens[2] == "number", let t = nounMap[tokens[1]], let idx = ordinalMap[tokens[3]] {
            return CopyIntent(target: .element(type: t, index: idx), rawTranscript: raw, normalizedTranscript: norm)
        }

        return nil
    }

    private func parseScope(from tokens: [String]) -> TargetScope? {
        let ordinalMap: [String: Int] = ["first": 1, "1st": 1, "second": 2, "2nd": 2, "third": 3, "3rd": 3, "fourth": 4, "4th": 4, "fifth": 5, "5th": 5]
        var t = tokens
        let articles: Set<String> = ["the", "this", "that", "a"]
        if let first = t.first, articles.contains(first) {
            t = Array(t.dropFirst())
        }

        if t.count >= 2, let idx = ordinalMap[t[0]] {
            if t[1] == "paragraph" { return .element(type: .paragraph, index: idx) }
            if t[1] == "heading" { return .element(type: .heading, index: idx) }
        }
        return nil
    }

    // MARK: - Selection Context Parser

    private func parseSelectionIntent(_ words: [String], raw: String, norm: String) -> CopyIntent? {
        guard words.first == "copy" else { return nil }
        let tokens = Array(words.dropFirst())
        guard !tokens.isEmpty else { return nil }

        let phrase = tokens.joined(separator: " ")

        // 1. Exact selection: "the selected text", "selected text", "my selection", "the selection", "selection", "what i selected", "what ive selected", "what i have selected"
        if phrase == "the selected text" || phrase == "selected text" || phrase == "my selection" ||
           phrase == "the selection" || phrase == "selection" || phrase == "what i selected" ||
           phrase == "what ive selected" || phrase == "what i ve selected" || phrase == "what i have selected" || phrase == "that i selected" {
            return CopyIntent(target: .selection(scope: .exact), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 2. Paragraph containing selection: "the paragraph i selected", "the paragraph that i selected", "paragraph i selected", "the selected paragraph", "selected paragraph"
        if phrase == "the paragraph i selected" || phrase == "the paragraph that i selected" ||
           phrase == "paragraph i selected" || phrase == "paragraph that i selected" ||
           phrase == "the selected paragraph" || phrase == "selected paragraph" ||
           phrase == "the paragraph ive selected" || phrase == "the paragraph i ve selected" || phrase == "the paragraph i have selected" {
            return CopyIntent(target: .selection(scope: .paragraph), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 3. Sentence containing selection: "the sentence i selected", "the sentence that i selected", "sentence i selected", "sentence that i selected", "the selected sentence", "selected sentence"
        if phrase == "the sentence i selected" || phrase == "the sentence that i selected" ||
           phrase == "sentence i selected" || phrase == "sentence that i selected" ||
           phrase == "the selected sentence" || phrase == "selected sentence" ||
           phrase == "the sentence ive selected" || phrase == "the sentence i ve selected" || phrase == "the sentence i have selected" {
            return CopyIntent(target: .selection(scope: .sentence), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 4. Containing text region: "the text i selected", "text i selected", "the text that i selected", "the text ive selected", "the text i have selected"
        if phrase == "the text i selected" || phrase == "text i selected" ||
           phrase == "the text that i selected" || phrase == "text that i selected" ||
           phrase == "the text ive selected" || phrase == "the text i ve selected" || phrase == "the text i have selected" {
            return CopyIntent(target: .selection(scope: .textRegion), rawTranscript: raw, normalizedTranscript: norm)
        }

        return nil
    }

    // MARK: - Pointer Context Parser

    private func parsePointerIntent(_ words: [String], raw: String, norm: String) -> CopyIntent? {
        guard words.first == "copy" else { return nil }
        let tokens = Array(words.dropFirst())
        guard !tokens.isEmpty else { return nil }

        let phrase = tokens.joined(separator: " ")

        // 1. Pointing / Hovering: "what i'm pointing at", "what i am pointing at", "what i'm pointing to", "what i am pointing to", "what i'm hovering over", "what i am hovering over", "what im pointing at", "what im pointing to", "what im hovering over"
        if phrase == "what im pointing at" || phrase == "what i m pointing at" || phrase == "what i am pointing at" ||
           phrase == "what im pointing to" || phrase == "what i m pointing to" || phrase == "what i am pointing to" ||
           phrase == "what im hovering over" || phrase == "what i m hovering over" || phrase == "what i am hovering over" ||
           phrase == "what im hovering on" || phrase == "what i m hovering on" || phrase == "what i am hovering on" ||
           phrase == "what im pointing" || phrase == "what i m pointing" || phrase == "what i am pointing" ||
           phrase == "what i point at" || phrase == "what i point to" {
            return CopyIntent(target: .pointerContext(relation: .under, scope: .all), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 2. Specific scope pointing: "the text i'm pointing to", "the text i am pointing to", "the text i'm pointing at", "the text i am pointing at", "the text im pointing to", "the text im pointing at"
        if phrase == "the text im pointing to" || phrase == "the text i m pointing to" || phrase == "the text i am pointing to" ||
           phrase == "the text im pointing at" || phrase == "the text i m pointing at" || phrase == "the text i am pointing at" ||
           phrase == "text im pointing to" || phrase == "text i m pointing to" || phrase == "text i am pointing to" ||
           phrase == "text im pointing at" || phrase == "text i m pointing at" || phrase == "text i am pointing at" ||
           phrase == "the text that im pointing to" || phrase == "the text that i m pointing to" || phrase == "the text that i am pointing to" {
            return CopyIntent(target: .pointerContext(relation: .under, scope: .text), rawTranscript: raw, normalizedTranscript: norm)
        }

        if phrase == "the paragraph im pointing to" || phrase == "the paragraph i m pointing to" || phrase == "the paragraph i am pointing to" ||
           phrase == "the paragraph im pointing at" || phrase == "the paragraph i m pointing at" || phrase == "the paragraph i am pointing at" ||
           phrase == "paragraph im pointing to" || phrase == "paragraph i m pointing to" || phrase == "paragraph i am pointing to" ||
           phrase == "paragraph im pointing at" || phrase == "paragraph i m pointing at" || phrase == "paragraph i am pointing at" {
            return CopyIntent(target: .pointerContext(relation: .under, scope: .paragraph), rawTranscript: raw, normalizedTranscript: norm)
        }

        if phrase == "the heading im pointing to" || phrase == "the heading i m pointing to" || phrase == "the heading i am pointing to" ||
           phrase == "the heading im pointing at" || phrase == "the heading i m pointing at" || phrase == "the heading i am pointing at" ||
           phrase == "heading im pointing to" || phrase == "heading i m pointing to" || phrase == "heading i am pointing to" {
            return CopyIntent(target: .pointerContext(relation: .under, scope: .heading), rawTranscript: raw, normalizedTranscript: norm)
        }

        // 3. Spatial relation relative to cursor/pointer/mouse
        // e.g. "the text under my cursor", "text above my cursor", "the paragraph under my cursor", "the heading under my cursor"
        let cursorNouns: Set<String> = ["cursor", "mouse", "pointer"]
        guard tokens.contains(where: { cursorNouns.contains($0) }) else { return nil }

        // Determine relation: under, above, below, next to
        var relation: PointerRelation? = nil
        var relationIndex: Int? = nil

        for (idx, tok) in tokens.enumerated() {
            if tok == "under" || tok == "at" || tok == "on" {
                relation = .under
                relationIndex = idx
                break
            } else if tok == "above" || tok == "over" {
                relation = .above
                relationIndex = idx
                break
            } else if tok == "below" || tok == "beneath" {
                relation = .below
                relationIndex = idx
                break
            } else if tok == "next" && idx + 1 < tokens.count && tokens[idx + 1] == "to" {
                relation = .nextTo
                relationIndex = idx
                break
            } else if tok == "beside" {
                relation = .nextTo
                relationIndex = idx
                break
            }
        }

        guard let rel = relation, let relIdx = relationIndex else { return nil }

        // Tokens preceding the relation describe the target scope: e.g. ["the", "paragraph"], ["the", "heading"], ["the", "text"], []
        let scopeTokens = tokens[0..<relIdx].filter { !["the", "this", "that", "a", "an"].contains($0) }
        let scopePhrase = scopeTokens.joined(separator: " ")

        let scope: PointerScope
        if scopePhrase == "paragraph" || scopePhrase == "paragraphs" {
            scope = .paragraph
        } else if scopePhrase == "heading" || scopePhrase == "headings" || scopePhrase == "header" || scopePhrase == "title" {
            scope = .heading
        } else if scopePhrase == "text" || scopePhrase == "texts" || scopePhrase == "content" || scopePhrase == "section" {
            scope = .text
        } else if scopePhrase.isEmpty {
            scope = .text
        } else {
            scope = .all
        }

        return CopyIntent(target: .pointerContext(relation: rel, scope: scope), rawTranscript: raw, normalizedTranscript: norm)
    }
}
