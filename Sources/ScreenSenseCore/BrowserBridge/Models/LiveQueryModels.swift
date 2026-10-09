import Foundation
import CoreGraphics

/// Types of live command-time queries sent to the browser extension
public enum LiveQueryType: String, Codable, Sendable {
    case activeTab = "active_tab"
    case activePointer = "active_pointer"
    case activeSelection = "active_selection"
    case activeDOM = "active_dom"
}

/// Request payload sent from ScreenSense to Chrome Extension
public struct LiveQueryRequest: Codable, Sendable {
    public let requestId: String
    public let type: LiveQueryType
    public let parameters: [String: String]?
    public let timestamp: Date

    public init(
        requestId: String = UUID().uuidString,
        type: LiveQueryType,
        parameters: [String: String]? = nil,
        timestamp: Date = Date()
    ) {
        self.requestId = requestId
        self.type = type
        self.parameters = parameters
        self.timestamp = timestamp
    }
}

/// Element details returned from elementFromPoint live extraction
public struct LiveTargetElement: Codable, Equatable, Sendable {
    public let id: String?
    public let tag: String?
    public let text: String?
    public let bounds: ElementBounds?
    public let type: String?
    public let selector: String?

    public init(
        id: String? = nil,
        tag: String? = nil,
        text: String? = nil,
        bounds: ElementBounds? = nil,
        type: String? = nil,
        selector: String? = nil
    ) {
        self.id = id
        self.tag = tag
        self.text = text
        self.bounds = bounds
        self.type = type
        self.selector = selector
    }
}

/// Live Pointer Query Result returned by active Chrome tab
public struct LivePointerResult: Codable, Equatable, Sendable {
    public let status: String // "OK", "POINTER_UNAVAILABLE", "ELEMENT_NOT_FOUND"
    public let x: Double
    public let y: Double
    public let targetElement: LiveTargetElement?
    public let containingText: String?
    public let containingParagraph: String?
    public let containingHeading: String?
    public let containingSection: String?

    public init(
        status: String = "OK",
        x: Double,
        y: Double,
        targetElement: LiveTargetElement? = nil,
        containingText: String? = nil,
        containingParagraph: String? = nil,
        containingHeading: String? = nil,
        containingSection: String? = nil
    ) {
        self.status = status
        self.x = x
        self.y = y
        self.targetElement = targetElement
        self.containingText = containingText
        self.containingParagraph = containingParagraph
        self.containingHeading = containingHeading
        self.containingSection = containingSection
    }
}

/// Live Selection Query Result returned by active Chrome tab
public struct LiveSelectionResult: Codable, Equatable, Sendable {
    public let status: String // "OK", "NO_ACTIVE_SELECTION"
    public let text: String
    public let isCollapsed: Bool
    public let bounds: ElementBounds?
    public let containingElementId: String?
    public let containingText: String?
    public let containingSentence: String?
    public let containingParagraph: String?

    public init(
        status: String = "OK",
        text: String,
        isCollapsed: Bool = false,
        bounds: ElementBounds? = nil,
        containingElementId: String? = nil,
        containingText: String? = nil,
        containingSentence: String? = nil,
        containingParagraph: String? = nil
    ) {
        self.status = status
        self.text = text
        self.isCollapsed = isCollapsed
        self.bounds = bounds
        self.containingElementId = containingElementId
        self.containingText = containingText
        self.containingSentence = containingSentence
        self.containingParagraph = containingParagraph
    }
}

/// Unified Response payload from Chrome Extension for all query types
public struct LiveQueryResponse: Codable, Sendable {
    public let requestId: String
    public let success: Bool
    public let status: String?
    public let error: String?
    public let tabId: String?
    public let url: String?
    public let pageTitle: String?
    public let viewport: ViewportInfo?
    public let pointerResult: LivePointerResult?
    public let selectionResult: LiveSelectionResult?
    public let domResult: VisibleContext?
    public let timestamp: Date

    public init(
        requestId: String,
        success: Bool,
        status: String? = nil,
        error: String? = nil,
        tabId: String? = nil,
        url: String? = nil,
        pageTitle: String? = nil,
        viewport: ViewportInfo? = nil,
        pointerResult: LivePointerResult? = nil,
        selectionResult: LiveSelectionResult? = nil,
        domResult: VisibleContext? = nil,
        timestamp: Date = Date()
    ) {
        self.requestId = requestId
        self.success = success
        self.status = status
        self.error = error
        self.tabId = tabId
        self.url = url
        self.pageTitle = pageTitle
        self.viewport = viewport
        self.pointerResult = pointerResult
        self.selectionResult = selectionResult
        self.domResult = domResult
        self.timestamp = timestamp
    }
}

/// Standardized Errors for Live Chrome Command Queries
public enum LiveQueryError: LocalizedError, Equatable, Sendable {
    case noActiveChromeTab
    case noActiveSelection
    case pointerUnavailable
    case queryTimeout
    case tabChangedDuringQuery
    case contentScriptUnavailable
    case liveQueryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveChromeTab:
            return "No active Google Chrome tab found to query."
        case .noActiveSelection:
            return "No text currently selected in active Chrome tab."
        case .pointerUnavailable:
            return "Pointer position is unavailable in active Chrome tab."
        case .queryTimeout:
            return "Live browser query timed out."
        case .tabChangedDuringQuery:
            return "Active tab changed during query execution."
        case .contentScriptUnavailable:
            return "ScreenSense extension content script is not loaded in this tab."
        case .liveQueryFailed(let reason):
            return "Live query failed: \(reason)"
        }
    }
}

