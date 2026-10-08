import Foundation
import CoreGraphics

/// Target resolution outcome
public enum TargetResolutionResult: Equatable, Sendable {
    case success(element: VisibleElement?, extractedText: String)
    case ambiguous(reason: String, candidateDescriptions: [String])
    case notFound(reason: String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Protocol for resolving structured IntentTargets against UnifiedContext
public protocol ContextTargetResolverProtocol: Sendable {
    func resolve(target: IntentTarget, in context: UnifiedContext) -> TargetResolutionResult
}

/// Deterministic target resolver operating on Universal UnifiedContext
public struct ContextTargetResolver: ContextTargetResolverProtocol, Sendable {
    private let semanticSelector: SemanticElementSelector

    public init(semanticSelector: SemanticElementSelector = SemanticElementSelector()) {
        self.semanticSelector = semanticSelector
    }

    public func resolve(target: IntentTarget, in context: UnifiedContext) -> TargetResolutionResult {
        ScreenSenseLogger.parser.info("[TARGET RESOLVER] Resolving target against \(context.applicationName, privacy: .public) with \(context.elements.count) elements")

        switch target {
        case .element(let type, let index):
            return resolveExplicitElement(type: type, index: index, in: context)

        case .semantic(let role, let topic):
            return resolveSemanticRole(role: role, topic: topic, in: context)

        case .spatial(let relationship, let referenceText, let referenceType):
            return resolveSpatialRelationship(relationship: relationship, referenceText: referenceText, referenceType: referenceType, in: context)

        case .pointerContext(let relation, let scope):
            return resolvePointerContext(relation: relation, scope: scope, in: context)

        case .selection(let scope):
            return resolveSelectionContext(scope: scope, in: context)

        case .wordRange(let scope, let range):
            return resolveWordRange(scope: scope, range: range, in: context)

        case .textRange(let scope, let range):
            return resolveTextRange(scope: scope, range: range, in: context)
        }
    }

    // MARK: - 1. Explicit Element Resolution

    private func resolveExplicitElement(type: ElementType, index: Int?, in context: UnifiedContext) -> TargetResolutionResult {
        let sorted = context.spatiallySortedElements
        let matchingElements: [VisibleElement]

        switch type {
        case .heading:
            matchingElements = sorted.filter {
                $0.type == .heading || ["h1", "h2", "h3", "h4", "h5", "h6"].contains($0.tag?.lowercased())
            }
        case .button:
            matchingElements = sorted.filter {
                $0.type == .button || $0.tag?.lowercased() == "button"
            }
        case .link:
            matchingElements = sorted.filter {
                $0.type == .link || $0.tag?.lowercased() == "a"
            }
        case .paragraph:
            // Human-centric paragraph resolution: meaningful text regions in natural reading order
            let paragraphCandidates = sorted.filter { el in
                if el.type == .heading { return false }
                if SemanticElementSelector.isNavigationOrBoilerplate(el) { return false }
                
                if el.type == .paragraph || el.tag?.lowercased() == "p" {
                    return !el.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                
                // Div or generic text block that has meaningful prose
                let trimmed = el.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let wordCount = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
                return wordCount >= 3 || trimmed.count >= 25
            }

            if !paragraphCandidates.isEmpty {
                matchingElements = paragraphCandidates
            } else if context.source == .ocr && !context.largeTextRegions.isEmpty {
                let regions = context.largeTextRegions.filter {
                    let mockEl = VisibleElement(type: .genericText, text: $0.text, bounds: $0.bounds ?? ElementBounds(x: 0, y: 0, width: 0, height: 0), source: .ocr)
                    return !SemanticElementSelector.isNavigationOrBoilerplate(mockEl)
                }
                if let requestedIndex = index {
                    guard requestedIndex >= 1 else {
                        return .notFound(reason: "Invalid paragraph index: \(requestedIndex)")
                    }
                    if requestedIndex <= regions.count {
                        let region = regions[requestedIndex - 1]
                        return .success(element: nil, extractedText: region.text)
                    } else {
                        let plural = regions.count == 1 ? "" : "s"
                        return .notFound(reason: "Only \(regions.count) visible paragraph\(plural) found.")
                    }
                }
                if regions.count == 1 {
                    return .success(element: nil, extractedText: regions[0].text)
                }
                return .ambiguous(
                    reason: "Multiple paragraphs visible (\(regions.count)). Please specify which paragraph.",
                    candidateDescriptions: regions.map { "'\($0.text.prefix(40))'" }
                )
            } else {
                matchingElements = sorted.filter { $0.type == .paragraph || $0.tag?.lowercased() == "p" }
            }
        default:
            matchingElements = sorted.filter { $0.type == type }
        }

        let typeNoun = type.rawValue

        if matchingElements.isEmpty {
            return .notFound(reason: "No visible \(typeNoun) found in \(context.applicationName).")
        }

        if let requestedIndex = index {
            guard requestedIndex >= 1 else {
                return .notFound(reason: "Invalid \(typeNoun) index: \(requestedIndex)")
            }

            if requestedIndex <= matchingElements.count {
                let element = matchingElements[requestedIndex - 1]
                return .success(element: element, extractedText: element.text)
            } else {
                let plural = matchingElements.count == 1 ? "" : "s"
                return .notFound(reason: "Only \(matchingElements.count) visible \(typeNoun)\(plural) found.")
            }
        }

        if matchingElements.count == 1 {
            let element = matchingElements[0]
            return .success(element: element, extractedText: element.text)
        }

        // When no index specified and multiple paragraph/text candidates exist, default to the first primary text block
        if type == .paragraph && !matchingElements.isEmpty {
            let element = matchingElements[0]
            return .success(element: element, extractedText: element.text)
        }

        let pluralNoun = typeNoun.hasSuffix("s") ? typeNoun : "\(typeNoun)s"
        return .ambiguous(
            reason: "Multiple \(pluralNoun) visible (\(matchingElements.count)). Please specify which \(typeNoun).",
            candidateDescriptions: matchingElements.map { "'\($0.text.prefix(40))'" }
        )
    }

    // MARK: - 2. Semantic Target Resolution

    private func resolveSemanticRole(role: String, topic: String?, in context: UnifiedContext) -> TargetResolutionResult {
        let normalizedRole = role.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let defaultViewport = context.viewport ?? ViewportInfo(width: 1920, height: 1080)

        // Delegate to specific content extraction for price / email
        if normalizedRole == "price" || normalizedRole == "currency" {
            let visCtx = VisibleContext(source: context.source, viewport: defaultViewport, elements: context.elements)
            let result = semanticSelector.select(intent: .price, in: visCtx)
            switch result {
            case .success(let el, let txt): return .success(element: el, extractedText: txt)
            case .ambiguous(let r, let c): return .ambiguous(reason: r, candidateDescriptions: c)
            case .notFound(let r): return .notFound(reason: r)
            }
        }

        if normalizedRole == "email" || normalizedRole == "email_address" {
            let visCtx = VisibleContext(source: context.source, viewport: defaultViewport, elements: context.elements)
            let result = semanticSelector.select(intent: .email, in: visCtx)
            switch result {
            case .success(let el, let txt): return .success(element: el, extractedText: txt)
            case .ambiguous(let r, let c): return .ambiguous(reason: r, candidateDescriptions: c)
            case .notFound(let r): return .notFound(reason: r)
            }
        }

        // Phone number pattern extraction
        if normalizedRole == "phone" || normalizedRole == "phone_number" {
            return extractPhoneNumber(in: context)
        }

        // Content / Topic search with candidate ranking: "text about X", "paragraph discussing Y"
        if let searchTopic = topic, !searchTopic.isEmpty {
            return resolveTopicQuery(topic: searchTopic, in: context)
        }

        // Company Name / Job Title / Person Name Resolution
        if normalizedRole == "company_name" || normalizedRole == "company" {
            return resolveCompanyOrJobEntity(role: "company", in: context)
        }

        if normalizedRole == "job_title" || normalizedRole == "job role" {
            return resolveCompanyOrJobEntity(role: "job_title", in: context)
        }

        // Title / Page Title / Article Title / Document Title Resolution
        if normalizedRole == "title" || normalizedRole == "page_title" || normalizedRole == "article_title" ||
           normalizedRole == "document_title" || normalizedRole == "main_title" || normalizedRole == "headline" {
            return resolveTitle(in: context)
        }

        // Default: search elements for text role or label
        let matching = context.elements.filter { el in
            StringNormalizer.normalize(el.text).contains(normalizedRole) ||
            el.id.lowercased().contains(normalizedRole)
        }

        if matching.count == 1 {
            return .success(element: matching[0], extractedText: matching[0].text)
        } else if matching.count > 1 {
            return .ambiguous(
                reason: "Multiple candidates found for '\(role)'.",
                candidateDescriptions: matching.map { "'\($0.text.prefix(40))'" }
            )
        }

        return .notFound(reason: "Could not find '\(role)' in the current context.")
    }

    // MARK: - Topic-Based Candidate Ranking

    private func resolveTopicQuery(topic: String, in context: UnifiedContext) -> TargetResolutionResult {
        let normTopic = StringNormalizer.normalize(topic)
        let topicTokens = normTopic.components(separatedBy: " ").filter { $0.count > 1 }

        guard !topicTokens.isEmpty else {
            return .notFound(reason: "Search topic cannot be empty.")
        }

        struct ScoredTopicCandidate {
            let element: VisibleElement?
            let text: String
            let score: Double
            let isParagraph: Bool
            let wordCount: Int
        }

        var candidates: [ScoredTopicCandidate] = []

        // 1. Gather all candidates from spatially sorted elements
        for el in context.spatiallySortedElements {
            let elText = el.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !elText.isEmpty else { continue }
            guard !SemanticElementSelector.isNavigationOrBoilerplate(el) else { continue }

            let normElText = StringNormalizer.normalize(elText)

            var score = 0.0

            // A. Exact phrase match
            if normElText.contains(normTopic) {
                score += 50.0
            }

            // B. Token overlap
            var matchedTokenCount = 0
            for token in topicTokens {
                if normElText.contains(token) {
                    matchedTokenCount += 1
                }
            }
            guard matchedTokenCount > 0 else { continue }

            let tokenRatio = Double(matchedTokenCount) / Double(topicTokens.count)
            score += tokenRatio * 30.0

            // C. Text Substance Bonus
            let words = elText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            let count = elText.count

            if count >= 80 { score += 15.0 }
            if count >= 200 { score += 15.0 }
            if elText.contains(".") || elText.contains(";") { score += 10.0 }

            // D. Paragraph/Text block type bonus
            let isPara = (el.type == .paragraph || el.tag?.lowercased() == "p" || words.count >= 10)
            if isPara {
                score += 15.0
            }

            // E. Single isolated link/button penalty
            if (el.type == .link || el.type == .button) && words.count < 6 {
                score -= 30.0
            }

            candidates.append(ScoredTopicCandidate(
                element: el,
                text: elText,
                score: score,
                isParagraph: isPara,
                wordCount: words.count
            ))
        }

        // 2. Also check largeTextRegions if OCR or structured DOM regions
        for region in context.largeTextRegions {
            let regText = region.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !regText.isEmpty else { continue }
            let normRegText = StringNormalizer.normalize(regText)

            var score = 0.0
            if normRegText.contains(normTopic) { score += 50.0 }
            var matchedTokenCount = 0
            for token in topicTokens {
                if normRegText.contains(token) { matchedTokenCount += 1 }
            }
            guard matchedTokenCount > 0 else { continue }

            let tokenRatio = Double(matchedTokenCount) / Double(topicTokens.count)
            score += tokenRatio * 30.0
            if regText.count >= 80 { score += 15.0 }
            if regText.count >= 200 { score += 15.0 }
            score += 20.0

            candidates.append(ScoredTopicCandidate(
                element: nil,
                text: regText,
                score: score,
                isParagraph: true,
                wordCount: regText.components(separatedBy: .whitespacesAndNewlines).count
            ))
        }

        // Filter and sort candidates by score descending
        let ranked = candidates.filter { $0.score >= 20.0 }.sorted { $0.score > $1.score }

        if ranked.isEmpty {
            return .notFound(reason: "No content about '\(topic)' found in current context.")
        }

        if ranked.count == 1 {
            return .success(element: ranked[0].element, extractedText: ranked[0].text)
        }

        let best = ranked[0]
        let second = ranked[1]

        // Clear lead: best score is significantly higher or best is a substantial paragraph
        if (best.score - second.score >= 8.0) || (best.isParagraph && !second.isParagraph) || (best.wordCount > second.wordCount * 2) {
            ScreenSenseLogger.parser.info("[TARGET RESOLVER] Topic query for '\(topic)' resolved to best candidate: score \(best.score) vs \(second.score)")
            return .success(element: best.element, extractedText: best.text)
        }

        // Ambiguous when two indistinguishable top candidates match
        let descriptions = ranked.prefix(4).map { "'\($0.text.prefix(60))...'" }
        return .ambiguous(
            reason: "Multiple sections discussing '\(topic)' found (\(ranked.count)). Please specify which section.",
            candidateDescriptions: Array(descriptions)
        )
    }

    // MARK: - 3. Spatial Relationship Resolution

    private func resolveSpatialRelationship(
        relationship: SpatialRelationship,
        referenceText: String,
        referenceType: ElementType?,
        in context: UnifiedContext
    ) -> TargetResolutionResult {
        let defaultViewport = context.viewport ?? ViewportInfo(width: 1920, height: 1080)
        let visCtx = VisibleContext(source: context.source, viewport: defaultViewport, elements: context.elements)

        switch relationship {
        case .below, .under:
            let ref: SemanticReference
            let normRef = StringNormalizer.normalize(referenceText)
            if normRef == "title" || normRef == "main title" || normRef == "heading" {
                ref = .title
            } else {
                ref = .heading(text: referenceText)
            }
            let res = semanticSelector.select(intent: .below(reference: ref), in: visCtx)
            switch res {
            case .success(let el, let txt): return .success(element: el, extractedText: txt)
            case .ambiguous(let r, let c): return .ambiguous(reason: r, candidateDescriptions: c)
            case .notFound(let r): return .notFound(reason: r)
            }

        case .nextTo:
            let ref: SemanticReference = .button(text: referenceText)
            let res = semanticSelector.select(intent: .nextTo(reference: ref), in: visCtx)
            switch res {
            case .success(let el, let txt): return .success(element: el, extractedText: txt)
            case .ambiguous(let r, let c): return .ambiguous(reason: r, candidateDescriptions: c)
            case .notFound(let r): return .notFound(reason: r)
            }

        default:
            return .notFound(reason: "Spatial relationship '\(relationship.rawValue)' is not yet supported.")
        }
    }

    // MARK: - 4. Word Range Resolution

    private func resolveWordRange(scope: TargetScope?, range: WordRange, in context: UnifiedContext) -> TargetResolutionResult {
        guard let sourceElement = resolveScopeElement(scope: scope, in: context) else {
            // Fall back to entire large text region or first available text element
            if let region = context.largeTextRegions.first {
                return extractWordRangeFromText(sourceText: region.text, element: nil, range: range)
            }
            if let firstEl = context.spatiallySortedElements.first(where: { !$0.text.isEmpty && !SemanticElementSelector.isNavigationOrBoilerplate($0) }) {
                return extractWordRangeFromText(sourceText: firstEl.text, element: firstEl, range: range)
            }
            return .notFound(reason: "No target element found for word range extraction.")
        }

        return extractWordRangeFromText(sourceText: sourceElement.text, element: sourceElement, range: range)
    }

    private func extractWordRangeFromText(sourceText: String, element: VisibleElement?, range: WordRange) -> TargetResolutionResult {
        let result = WordRangeResolver.extractWords(from: sourceText, range: range)
        switch result {
        case .success(let words):
            return .success(element: element, extractedText: words)
        case .failure(let error):
            switch error {
            case .emptySourceText:
                return .notFound(reason: "Source text is empty.")
            case .invalidRange(let start, let end, let total):
                return .notFound(reason: "Requested word range \(start)..\(end) is out of bounds (element contains \(total) words).")
            default:
                return .notFound(reason: "Failed to extract word range: \(error)")
            }
        }
    }

    // MARK: - 5. Text Range Resolution

    private func resolveTextRange(scope: TargetScope?, range: TextRange, in context: UnifiedContext) -> TargetResolutionResult {
        if let sourceElement = resolveScopeElement(scope: scope, in: context) {
            let res = WordRangeResolver.extractTextRange(from: sourceElement.text, range: range)
            switch res {
            case .success(let txt): return .success(element: sourceElement, extractedText: txt)
            case .failure(let err): return .notFound(reason: "Range extraction failed: \(err)")
            }
        }

        // Search across all text regions/elements in context
        for el in context.spatiallySortedElements {
            let res = WordRangeResolver.extractTextRange(from: el.text, range: range)
            if case .success(let txt) = res {
                return .success(element: el, extractedText: txt)
            }
        }

        for region in context.largeTextRegions {
            let res = WordRangeResolver.extractTextRange(from: region.text, range: range)
            if case .success(let txt) = res {
                return .success(element: nil, extractedText: txt)
            }
        }

        return .notFound(reason: "Could not find text range from '\(range.startText)' to '\(range.endText)'.")
    }

    // MARK: - Helper Methods

    private func resolveScopeElement(scope: TargetScope?, in context: UnifiedContext) -> VisibleElement? {
        guard let scope = scope else { return nil }
        switch scope {
        case .element(let type, let index):
            if type == .paragraph && context.source == .ocr && !context.largeTextRegions.isEmpty {
                if let idx = index, idx >= 1 && idx <= context.largeTextRegions.count {
                    let region = context.largeTextRegions[idx - 1]
                    return VisibleElement(
                        id: region.id,
                        type: .paragraph,
                        text: region.text,
                        bounds: region.bounds ?? ElementBounds(x: 0, y: 0, width: 0, height: 0),
                        source: .ocr
                    )
                }
            }
            let matching = context.spatiallySortedElements.filter {
                $0.type == type || ($0.source == .ocr && type == .paragraph && $0.type == .genericText)
            }
            if let idx = index, idx >= 1 && idx <= matching.count {
                return matching[idx - 1]
            }
            return matching.first
        case .heading(let text):
            let norm = StringNormalizer.normalize(text)
            return context.spatiallySortedElements.first { $0.type == .heading && StringNormalizer.normalize($0.text).contains(norm) }
        case .selector(let sel):
            return context.elements.first { $0.selector == sel || $0.id == sel }
        default:
            return context.spatiallySortedElements.first
        }
    }

    private func extractPhoneNumber(in context: UnifiedContext) -> TargetResolutionResult {
        let phoneRegex = try! NSRegularExpression(
            pattern: #"(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#,
            options: []
        )

        var foundPhones: [(phone: String, element: VisibleElement)] = []
        for el in context.elements {
            let text = el.text
            let range = NSRange(location: 0, length: (text as NSString).length)
            let matches = phoneRegex.matches(in: text, options: [], range: range)
            for m in matches {
                if let r = Range(m.range, in: text) {
                    foundPhones.append((phone: String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines), element: el))
                }
            }
        }

        let unique = Dictionary(grouping: foundPhones, by: { $0.phone.lowercased() })
        if unique.isEmpty {
            return .notFound(reason: "No visible phone number found.")
        }
        if unique.count == 1, let single = unique.values.first?.first {
            return .success(element: single.element, extractedText: single.phone)
        }
        return .ambiguous(reason: "Multiple phone numbers found (\(unique.count)).", candidateDescriptions: unique.keys.map { $0 })
    }

    private func resolveTitle(in context: UnifiedContext) -> TargetResolutionResult {
        // Priority 1: Page/Article title metadata (from DOM viewport)
        if let pageTitle = context.viewport?.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !pageTitle.isEmpty {
            ScreenSenseLogger.parser.info("[TARGET RESOLVER] Resolved title to viewport.pageTitle metadata: '\(pageTitle, privacy: .public)'")
            return .success(element: nil, extractedText: pageTitle)
        }

        // Priority 2: Page title from metadata dictionary
        if let metaTitle = context.metadata["page_title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !metaTitle.isEmpty {
            ScreenSenseLogger.parser.info("[TARGET RESOLVER] Resolved title to metadata['page_title']: '\(metaTitle, privacy: .public)'")
            return .success(element: nil, extractedText: metaTitle)
        }

        // Priority 3: Window title (document.title captured in windowInfo)
        if let winTitle = context.windowInfo?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !winTitle.isEmpty,
           !["Google Chrome", "Chrome", "ScreenSense", "Desktop", "Active Window"].contains(winTitle) {
            ScreenSenseLogger.parser.info("[TARGET RESOLVER] Resolved title to windowInfo.title: '\(winTitle, privacy: .public)'")
            return .success(element: nil, extractedText: winTitle)
        }

        // Priority 4: Visible H1 element at top of document
        if let h1 = context.spatiallySortedElements.first(where: {
            let isH1Tag = $0.tag?.lowercased() == "h1"
            let isProminentHeading = $0.type == .heading && ($0.bounds.height >= 24 || $0.bounds.width >= 200)
            return (isH1Tag || isProminentHeading) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            ScreenSenseLogger.parser.info("[TARGET RESOLVER] Resolved title to visible H1: '\(h1.text, privacy: .public)'")
            return .success(element: h1, extractedText: h1.text)
        }

        // Priority 5: Spatially first heading
        if let firstHeading = context.spatiallySortedElements.first(where: { $0.type == .heading && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            ScreenSenseLogger.parser.info("[TARGET RESOLVER] Resolved title to first visible heading: '\(firstHeading.text, privacy: .public)'")
            return .success(element: firstHeading, extractedText: firstHeading.text)
        }

        return .notFound(reason: "No visible title or document title found in current context.")
    }

    private func resolveCompanyOrJobEntity(role: String, in context: UnifiedContext) -> TargetResolutionResult {
        // Look for headings, prominent titles, or metadata
        let headings = context.spatiallySortedElements.filter { $0.type == .heading && !SemanticElementSelector.isNavigationOrBoilerplate($0) }
        if let firstHeading = headings.first {
            return .success(element: firstHeading, extractedText: firstHeading.text)
        }
        let paragraphs = context.spatiallySortedElements.filter { $0.type == .paragraph && !SemanticElementSelector.isNavigationOrBoilerplate($0) }
        if let firstP = paragraphs.first {
            return .success(element: firstP, extractedText: firstP.text)
        }
        return .notFound(reason: "No visible \(role) found in current context.")
    }

    // MARK: - Pointer Context Resolution

    private func resolvePointerContext(relation: PointerRelation, scope: PointerScope?, in context: UnifiedContext) -> TargetResolutionResult {
        guard let pointer = context.pointer else {
            return .notFound(reason: "No pointer/cursor position available in current context.")
        }

        let px = pointer.x
        let py = pointer.y

        let sorted = context.spatiallySortedElements.filter {
            !SemanticElementSelector.isNavigationOrBoilerplate($0)
        }

        switch relation {
        case .under:
            // 1. Check direct containment: bounds contains (px, py)
            var directHits = sorted.filter { el in
                el.bounds.x <= px && (el.bounds.x + el.bounds.width) >= px &&
                el.bounds.y <= py && (el.bounds.y + el.bounds.height) >= py
            }

            // If no direct hit, check elements within a proximity tolerance (20px)
            if directHits.isEmpty {
                directHits = sorted.filter { el in
                    let dx = max(0, max(el.bounds.x - px, px - (el.bounds.x + el.bounds.width)))
                    let dy = max(0, max(el.bounds.y - py, py - (el.bounds.y + el.bounds.height)))
                    return hypot(dx, dy) <= 20.0
                }
            }

            if directHits.isEmpty {
                // Check large text regions if any
                for region in context.largeTextRegions {
                    if let b = region.bounds, b.x <= px && (b.x + b.width) >= px && b.y <= py && (b.y + b.height) >= py {
                        return .success(element: nil, extractedText: region.text)
                    }
                }
                return .notFound(reason: "No visible text under cursor.")
            }

            // Filter or score based on scope
            if scope == .heading {
                if let heading = directHits.first(where: { $0.type == .heading || ["h1", "h2", "h3", "h4", "h5", "h6"].contains($0.tag?.lowercased()) }) {
                    return .success(element: heading, extractedText: heading.text)
                }
            }

            if scope == .paragraph {
                // Look for containing paragraph / substantive text block
                if let para = directHits.first(where: { $0.type == .paragraph || $0.tag?.lowercased() == "p" || $0.text.count >= 40 }) {
                    return .success(element: para, extractedText: para.text)
                }
            }

            // General / text scope:
            // If the element under cursor is a tiny inline element (like a link or span inside a paragraph), find the containing paragraph
            let smallest = directHits.min(by: { ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height) }) ?? directHits[0]

            // If smallest is a small link or button, but there's a containing paragraph, return the paragraph
            if (smallest.type == .link || smallest.type == .button || smallest.text.count < 30) {
                if let containingPara = directHits.first(where: { ($0.type == .paragraph || $0.tag?.lowercased() == "p" || $0.text.count >= 40) && $0.id != smallest.id }) {
                    return .success(element: containingPara, extractedText: containingPara.text)
                }
            }

            return .success(element: smallest, extractedText: smallest.text)

        case .above:
            // Elements strictly above cursor (bounds.y + bounds.height <= py or bounds.y < py)
            let aboveElements = sorted.filter { ($0.bounds.y + $0.bounds.height) <= py + 5 }
            guard !aboveElements.isEmpty else {
                return .notFound(reason: "No visible text found above cursor.")
            }

            // Sort by vertical distance to pointer (closest bottom edge to py)
            let ranked = aboveElements.sorted {
                let distA = py - ($0.bounds.y + $0.bounds.height)
                let distB = py - ($1.bounds.y + $1.bounds.height)
                return distA < distB
            }

            if scope == .paragraph || scope == .text {
                if let para = ranked.first(where: { $0.type == .paragraph || $0.text.count >= 30 }) {
                    return .success(element: para, extractedText: para.text)
                }
            }
            return .success(element: ranked[0], extractedText: ranked[0].text)

        case .below:
            // Elements strictly below cursor (bounds.y >= py - 5)
            let belowElements = sorted.filter { $0.bounds.y >= py - 5 }
            guard !belowElements.isEmpty else {
                return .notFound(reason: "No visible text found below cursor.")
            }

            // Sort by vertical distance to pointer (closest top edge to py)
            let ranked = belowElements.sorted {
                let distA = $0.bounds.y - py
                let distB = $1.bounds.y - py
                return distA < distB
            }

            if scope == .paragraph || scope == .text {
                if let para = ranked.first(where: { $0.type == .paragraph || $0.text.count >= 30 }) {
                    return .success(element: para, extractedText: para.text)
                }
            }
            return .success(element: ranked[0], extractedText: ranked[0].text)

        case .nextTo:
            // Elements horizontally adjacent (overlapping Y or near Y)
            let adjacent = sorted.filter { el in
                let yOverlap = max(0, min(el.bounds.y + el.bounds.height, py + 20) - max(el.bounds.y, py - 20))
                return yOverlap > 0
            }
            guard !adjacent.isEmpty else {
                return .notFound(reason: "No visible text found next to cursor.")
            }

            let ranked = adjacent.sorted {
                let distA = min(abs($0.bounds.x - px), abs($0.bounds.x + $0.bounds.width - px))
                let distB = min(abs($1.bounds.x - px), abs($1.bounds.x + $1.bounds.width - px))
                return distA < distB
            }
            return .success(element: ranked[0], extractedText: ranked[0].text)
        }
    }

    // MARK: - Selection Context Resolution

    private func resolveSelectionContext(scope: SelectionScope, in context: UnifiedContext) -> TargetResolutionResult {
        guard let selection = context.selection, !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .notFound(reason: "No text currently selected.")
        }

        let selText = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch scope {
        case .exact:
            return .success(element: nil, extractedText: selText)

        case .paragraph, .textRegion:
            // 1. Check containingElementId if present
            if let elId = selection.containingElementId, let el = context.elements.first(where: { $0.id == elId }) {
                return .success(element: el, extractedText: el.text)
            }

            // 2. Find element in context that contains the selected text
            if let el = context.spatiallySortedElements.first(where: { $0.text.contains(selText) && ($0.type == .paragraph || $0.text.count >= selText.count) }) {
                return .success(element: el, extractedText: el.text)
            }

            // 3. Fall back to any element containing selection
            if let el = context.elements.first(where: { $0.text.contains(selText) }) {
                return .success(element: el, extractedText: el.text)
            }

            // 4. Large text regions
            if let region = context.largeTextRegions.first(where: { $0.text.contains(selText) }) {
                return .success(element: nil, extractedText: region.text)
            }

            return .success(element: nil, extractedText: selText)

        case .sentence:
            // Find containing element text
            var fullText = selText
            var containingEl: VisibleElement? = nil

            if let elId = selection.containingElementId, let el = context.elements.first(where: { $0.id == elId }) {
                fullText = el.text
                containingEl = el
            } else if let el = context.spatiallySortedElements.first(where: { $0.text.contains(selText) }) {
                fullText = el.text
                containingEl = el
            } else if let region = context.largeTextRegions.first(where: { $0.text.contains(selText) }) {
                fullText = region.text
            }

            // Extract sentence containing selection
            let sentence = extractSentenceContaining(selection: selText, in: fullText)
            return .success(element: containingEl, extractedText: sentence)
        }
    }

    private func extractSentenceContaining(selection: String, in text: String) -> String {
        let cleanText = text.replacingOccurrences(of: "\n", with: " ")
        let pattern = #"[^.!?]+[.!?]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let nsString = cleanText as NSString
        let matches = regex.matches(in: cleanText, options: [], range: NSRange(location: 0, length: nsString.length))

        for m in matches {
            let sentence = nsString.substring(with: m.range).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.contains(selection) {
                return sentence
            }
        }

        return text
    }
}
