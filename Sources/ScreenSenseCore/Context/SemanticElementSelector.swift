import Foundation
import CoreGraphics

/// Target reference for semantic spatial relationships
public enum SemanticReference: Equatable, Sendable, CustomStringConvertible {
    case title // Topmost heading/title
    case heading(text: String) // Heading matching specific text
    case button(text: String) // Button matching specific text
    case element(type: ElementType, text: String?)

    public var description: String {
        switch self {
        case .title:
            return "Title"
        case .heading(let text):
            return "Heading '\(text)'"
        case .button(let text):
            return text.isEmpty ? "Button" : "Button '\(text)'"
        case .element(let type, let text):
            return "\(type.rawValue) '\(text ?? "")'"
        }
    }
}

/// Intent representing what semantic element or content to select
public enum SemanticSelectionIntent: Equatable, Sendable, CustomStringConvertible {
    case below(reference: SemanticReference)
    case nextTo(reference: SemanticReference)
    case email
    case price

    public var description: String {
        switch self {
        case .below(let ref):
            return "Below \(ref)"
        case .nextTo(let ref):
            return "Next To \(ref)"
        case .email:
            return "Email Address"
        case .price:
            return "Price"
        }
    }
}

/// Result of evaluating a semantic selection against DOMContext
public enum SemanticSelectionResult: Equatable, Sendable {
    case success(element: VisibleElement, extractedText: String)
    case notFound(reason: String)
    case ambiguous(reason: String, candidateDescriptions: [String])

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Protocol for semantic element selection
public protocol SemanticElementSelectorProtocol: Sendable {
    func select(intent: SemanticSelectionIntent, in context: VisibleContext) -> SemanticSelectionResult
}

/// Deterministic semantic selector operating strictly on DOMContext geometry and text patterns
public struct SemanticElementSelector: SemanticElementSelectorProtocol, Sendable {
    public init() {}

    public func select(intent: SemanticSelectionIntent, in context: VisibleContext) -> SemanticSelectionResult {
        ScreenSenseLogger.parser.info("[SEMANTIC INTENT] \(intent.description, privacy: .public)")

        switch intent {
        case .below(let reference):
            return selectBelow(reference: reference, in: context)
        case .nextTo(let reference):
            return selectNextTo(reference: reference, in: context)
        case .email:
            return selectEmail(in: context)
        case .price:
            return selectPrice(in: context)
        }
    }

    // MARK: - 1. Text Below Reference

    private func selectBelow(reference: SemanticReference, in context: VisibleContext) -> SemanticSelectionResult {
        let elements = context.spatiallySortedElements
        guard !elements.isEmpty else {
            return .notFound(reason: "No visible browser content available")
        }

        // 1. Identify reference element
        let refElement: VisibleElement
        switch reference {
        case .title:
            let headings = elements.filter { isHeading($0) }
            guard let firstHeading = headings.first else {
                return .notFound(reason: "No visible title or heading found")
            }
            refElement = firstHeading

        case .heading(let searchText):
            let normalizedSearch = StringNormalizer.normalize(searchText)
            let matchingHeadings = elements.filter { el in
                guard isHeading(el) else { return false }
                let normEl = StringNormalizer.normalize(el.text)
                return normEl.contains(normalizedSearch) ||
                       normalizedSearch.contains(normEl) ||
                       matchesHeadingOrdinal(elText: normEl, searchText: normalizedSearch)
            }

            if matchingHeadings.isEmpty {
                return .notFound(reason: "No visible heading matching '\(searchText)' found")
            }
            if matchingHeadings.count > 1 {
                let descs = matchingHeadings.map { "'\($0.text)'" }
                return .ambiguous(
                    reason: "Multiple headings matching '\(searchText)' visible (\(matchingHeadings.count)).",
                    candidateDescriptions: descs
                )
            }
            refElement = matchingHeadings[0]

        case .element(let type, let searchText):
            let candidates = elements.filter { el in
                el.type == type && (searchText == nil || StringNormalizer.normalize(el.text).contains(StringNormalizer.normalize(searchText!)))
            }
            if candidates.isEmpty {
                return .notFound(reason: "No visible reference element found")
            }
            if candidates.count > 1 {
                return .ambiguous(
                    reason: "Multiple reference elements visible (\(candidates.count)).",
                    candidateDescriptions: candidates.map { "'\($0.text)'" }
                )
            }
            refElement = candidates[0]

        case .button:
            return .notFound(reason: "Invalid reference type for 'below' query")
        }

        let refRect = refElement.bounds.cgRect
        let refBottom = refRect.maxY

        // 2. Filter candidates below the reference heading
        // Candidate must be visible, positioned below the heading, non-empty, and NOT another heading
        let belowCandidates = elements.filter { cand in
            guard cand.id != refElement.id else { return false }
            guard !isHeading(cand) else { return false }
            let candText = cand.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candText.isEmpty else { return false }

            let candTop = cand.bounds.y
            // Top of candidate must be at or below the reference bottom (with slight tolerance)
            return candTop >= (refRect.minY + refRect.height * 0.5) && candTop >= (refBottom - 8)
        }

        if belowCandidates.isEmpty {
            return .notFound(reason: "No visible text found below '\(refElement.text)'")
        }

        // 3. Score candidates by vertical distance and horizontal alignment
        struct ScoredCandidate {
            let element: VisibleElement
            let verticalDistance: Double
            let horizontalOffset: Double
            let totalScore: Double
        }

        let scored: [ScoredCandidate] = belowCandidates.map { cand in
            let candRect = cand.bounds.cgRect
            let verticalDist = max(0, candRect.minY - refBottom)
            let horizontalOffset = abs(candRect.midX - refRect.midX)

            // Prefer paragraph/text elements
            var typeBonus = 0.0
            if cand.type == .paragraph || cand.tag?.lowercased() == "p" {
                typeBonus = -5.0
            }

            let totalScore = verticalDist + (horizontalOffset * 0.2) + typeBonus
            return ScoredCandidate(
                element: cand,
                verticalDistance: verticalDist,
                horizontalOffset: horizontalOffset,
                totalScore: totalScore
            )
        }.sorted { $0.totalScore < $1.totalScore }

        guard let best = scored.first else {
            return .notFound(reason: "No visible text found below '\(refElement.text)'")
        }

        // Ambiguity check: if top 2 candidates are virtually equidistant
        if scored.count > 1 {
            let second = scored[1]
            if abs(second.totalScore - best.totalScore) < 1.0 && abs(second.verticalDistance - best.verticalDistance) < 2.0 {
                let descs = [best.element.text, second.element.text].map { "'\($0.prefix(40))'" }
                return .ambiguous(
                    reason: "Multiple text elements equally close below '\(refElement.text)'.",
                    candidateDescriptions: descs
                )
            }
        }

        ScreenSenseLogger.parser.info("[SEMANTIC SELECTOR] Selected '\(best.element.text, privacy: .public)' below '\(refElement.text, privacy: .public)'")
        return .success(element: best.element, extractedText: best.element.text)
    }

    // MARK: - 2. Text Next To Button

    private func selectNextTo(reference: SemanticReference, in context: VisibleContext) -> SemanticSelectionResult {
        let elements = context.spatiallySortedElements
        guard !elements.isEmpty else {
            return .notFound(reason: "No visible browser content available")
        }

        let refElement: VisibleElement
        switch reference {
        case .button(let searchText):
            let normalizedSearch = StringNormalizer.normalize(searchText)
            let buttons = elements.filter { $0.type == .button || $0.tag?.lowercased() == "button" }
            if buttons.isEmpty {
                return .notFound(reason: "No visible button found")
            }

            if normalizedSearch.isEmpty || normalizedSearch == "button" || normalizedSearch == "the button" {
                if buttons.count == 1 {
                    refElement = buttons[0]
                } else {
                    let candidates = buttons.map { "'\($0.text)'" }
                    return .ambiguous(
                        reason: "Multiple buttons visible (\(buttons.count)). Please specify which button.",
                        candidateDescriptions: candidates
                    )
                }
            } else {
                let matching = buttons.filter { btn in
                    let normalizedBtn = StringNormalizer.normalize(btn.text)
                    return normalizedBtn.contains(normalizedSearch) || normalizedSearch.contains(normalizedBtn)
                }
                if matching.isEmpty {
                    return .notFound(reason: "No visible button matching '\(searchText)' found")
                }
                if matching.count > 1 {
                    let candidates = matching.map { "'\($0.text)'" }
                    return .ambiguous(
                        reason: "Multiple buttons matching '\(searchText)' found (\(matching.count)).",
                        candidateDescriptions: candidates
                    )
                }
                refElement = matching[0]
            }

        default:
            return .notFound(reason: "Unsupported reference type for 'next to'")
        }

        let refRect = refElement.bounds.cgRect

        // Filter candidates positioned horizontally near the button (with vertical overlap or close center alignment)
        let candidates = elements.filter { cand in
            guard cand.id != refElement.id else { return false }
            let candText = cand.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candText.isEmpty else { return false }

            let candRect = cand.bounds.cgRect

            // Vertical overlap or vertical proximity
            let verticalOverlap = max(0, min(candRect.maxY, refRect.maxY) - max(candRect.minY, refRect.minY))
            let verticalCenterDist = abs(candRect.midY - refRect.midY)
            let isVerticallyAligned = verticalOverlap > 0 || verticalCenterDist <= max(refRect.height, candRect.height) * 1.5

            guard isVerticallyAligned else { return false }

            // Horizontal distance calculation
            let horizontalDistance: Double
            if candRect.minX >= refRect.maxX - 5 {
                horizontalDistance = candRect.minX - refRect.maxX
            } else if candRect.maxX <= refRect.minX + 5 {
                horizontalDistance = refRect.minX - candRect.maxX
            } else {
                horizontalDistance = abs(candRect.midX - refRect.midX)
            }

            return horizontalDistance <= 500
        }

        if candidates.isEmpty {
            return .notFound(reason: "No visible text found next to button '\(refElement.text)'")
        }

        struct ScoredNextToCandidate {
            let element: VisibleElement
            let horizontalDistance: Double
            let verticalCenterDist: Double
            let totalScore: Double
        }

        let scored = candidates.map { cand in
            let candRect = cand.bounds.cgRect
            let hDist: Double
            if candRect.minX >= refRect.maxX - 5 {
                hDist = candRect.minX - refRect.maxX
            } else if candRect.maxX <= refRect.minX + 5 {
                hDist = refRect.minX - candRect.maxX
            } else {
                hDist = abs(candRect.midX - refRect.midX)
            }
            let vCenterDist = abs(candRect.midY - refRect.midY)
            let score = hDist + (vCenterDist * 0.5)
            return ScoredNextToCandidate(element: cand, horizontalDistance: hDist, verticalCenterDist: vCenterDist, totalScore: score)
        }.sorted { $0.totalScore < $1.totalScore }

        guard let best = scored.first else {
            return .notFound(reason: "No visible text found next to button '\(refElement.text)'")
        }

        if scored.count > 1 {
            let second = scored[1]
            if abs(second.totalScore - best.totalScore) < 2.0 {
                let descs = [best.element.text, second.element.text].map { "'\($0.prefix(40))'" }
                return .ambiguous(
                    reason: "Multiple elements found next to button '\(refElement.text)'.",
                    candidateDescriptions: descs
                )
            }
        }

        ScreenSenseLogger.parser.info("[SEMANTIC SELECTOR] Selected '\(best.element.text, privacy: .public)' next to button '\(refElement.text, privacy: .public)'")
        return .success(element: best.element, extractedText: best.element.text)
    }

    // MARK: - 3. Email Address Extraction

    private func selectEmail(in context: VisibleContext) -> SemanticSelectionResult {
        let elements = context.spatiallySortedElements
        guard !elements.isEmpty else {
            return .notFound(reason: "No visible browser content available")
        }

        let emailRegex = try! NSRegularExpression(
            pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
            options: []
        )

        struct EmailMatch {
            let email: String
            let element: VisibleElement
        }

        var foundMatches: [EmailMatch] = []
        for el in elements {
            let text = el.text
            let range = NSRange(location: 0, length: (text as NSString).length)
            let matches = emailRegex.matches(in: text, options: [], range: range)
            for m in matches {
                if let r = Range(m.range, in: text) {
                    let emailStr = String(text[r])
                    foundMatches.append(EmailMatch(email: emailStr, element: el))
                }
            }
        }

        var uniqueEmails: [String: EmailMatch] = [:]
        for match in foundMatches {
            let key = match.email.lowercased()
            if uniqueEmails[key] == nil {
                uniqueEmails[key] = match
            }
        }

        if uniqueEmails.isEmpty {
            return .notFound(reason: "No visible email address found.")
        }

        if uniqueEmails.count == 1, let single = uniqueEmails.values.first {
            ScreenSenseLogger.parser.info("[SEMANTIC SELECTOR] Extracted email '\(single.email, privacy: .public)'")
            return .success(element: single.element, extractedText: single.email)
        }

        let emailList = uniqueEmails.values.map { $0.email }
        return .ambiguous(
            reason: "Multiple email addresses are visible (\(uniqueEmails.count)). Please specify which one.",
            candidateDescriptions: emailList
        )
    }

    // MARK: - 4. Price Extraction

    private func selectPrice(in context: VisibleContext) -> SemanticSelectionResult {
        let elements = context.spatiallySortedElements
        guard !elements.isEmpty else {
            return .notFound(reason: "No visible browser content available")
        }

        let priceRegex = try! NSRegularExpression(
            pattern: #"(?:[₹$€£¥]|USD|INR|EUR|GBP)\s?[0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?\s?(?:[₹$€£¥]|USD|INR|EUR|GBP)"#,
            options: []
        )

        struct PriceMatch {
            let price: String
            let element: VisibleElement
        }

        var foundMatches: [PriceMatch] = []
        for el in elements {
            let text = el.text
            let range = NSRange(location: 0, length: (text as NSString).length)
            let matches = priceRegex.matches(in: text, options: [], range: range)
            for m in matches {
                if let r = Range(m.range, in: text) {
                    let priceStr = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                    foundMatches.append(PriceMatch(price: priceStr, element: el))
                }
            }
        }

        var uniquePrices: [String: PriceMatch] = [:]
        for match in foundMatches {
            let key = match.price.lowercased().replacingOccurrences(of: " ", with: "")
            if uniquePrices[key] == nil {
                uniquePrices[key] = match
            }
        }

        if uniquePrices.isEmpty {
            return .notFound(reason: "No visible price found.")
        }

        if uniquePrices.count == 1, let single = uniquePrices.values.first {
            ScreenSenseLogger.parser.info("[SEMANTIC SELECTOR] Extracted price '\(single.price, privacy: .public)'")
            return .success(element: single.element, extractedText: single.price)
        }

        let priceList = uniquePrices.values.map { $0.price }
        return .ambiguous(
            reason: "Multiple prices are visible (\(uniquePrices.count)). Please specify which price.",
            candidateDescriptions: priceList
        )
    }

    // MARK: - Helper Methods

    private func isHeading(_ element: VisibleElement) -> Bool {
        if element.type == .heading { return true }
        if let tag = element.tag?.lowercased(), ["h1", "h2", "h3", "h4", "h5", "h6"].contains(tag) {
            return true
        }
        return false
    }

    private func matchesHeadingOrdinal(elText: String, searchText: String) -> Bool {
        if elText == searchText { return true }
        let normalizedSearch = searchText
            .replacingOccurrences(of: "heading to", with: "heading 2")
            .replacingOccurrences(of: "heading too", with: "heading 2")
            .replacingOccurrences(of: "heading won", with: "heading 1")
            .replacingOccurrences(of: "heading for", with: "heading 4")

        if elText == normalizedSearch { return true }
        if (normalizedSearch == "heading 2" || normalizedSearch == "heading two") &&
           (elText.contains("heading two") || elText.contains("heading 2")) { return true }
        if (normalizedSearch == "heading 1" || normalizedSearch == "heading one") &&
           (elText.contains("heading one") || elText.contains("heading 1")) { return true }
        if (normalizedSearch == "heading 3" || normalizedSearch == "heading three") &&
           (elText.contains("heading three") || elText.contains("heading 3")) { return true }
        if (normalizedSearch == "heading 4" || normalizedSearch == "heading four") &&
           (elText.contains("heading four") || elText.contains("heading 4")) { return true }
        return false
    }
}
