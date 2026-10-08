import Foundation
import CoreGraphics

/// Source from which the context or element was derived
public enum ContextSource: String, Codable, Equatable, Sendable {
    case dom = "dom"
    case screen = "screen"
    case unified = "unified"
    case accessibility = "accessibility"
    case ocr = "ocr"
    case vision = "vision"
}

/// Semantic type of a visible UI/text element
public enum ElementType: String, Codable, Equatable, Sendable {
    case heading = "heading"
    case paragraph = "paragraph"
    case listItem = "list_item"
    case blockquote = "blockquote"
    case code = "code"
    case button = "button"
    case link = "link"
    case input = "input"
    case genericText = "generic_text"
}

/// Spatial bounds of an element in viewport coordinates (and document coordinates where available)
public struct ElementBounds: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let documentX: Double?
    public let documentY: Double?

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        documentX: Double? = nil,
        documentY: Double? = nil
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.documentX = documentX
        self.documentY = documentY
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Viewport and document dimensions at capture time
public struct ViewportInfo: Codable, Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let scrollX: Double
    public let scrollY: Double
    public let devicePixelRatio: Double
    public let pageTitle: String?
    public let url: String?

    public init(
        width: Double,
        height: Double,
        scrollX: Double = 0,
        scrollY: Double = 0,
        devicePixelRatio: Double = 1.0,
        pageTitle: String? = nil,
        url: String? = nil
    ) {
        self.width = width
        self.height = height
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.devicePixelRatio = devicePixelRatio
        self.pageTitle = pageTitle
        self.url = url
    }
}

/// A discrete visible element extracted from DOM, OCR, or Accessibility
public struct VisibleElement: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let type: ElementType
    public let text: String
    public let bounds: ElementBounds
    public let visibilityPercentage: Double // 0.0 to 1.0 (100% visible)
    public let confidence: Double          // 1.0 for DOM, variable for OCR/Vision
    public let source: ContextSource
    public let tag: String?
    public let selector: String?

    public init(
        id: String = UUID().uuidString,
        type: ElementType,
        text: String,
        bounds: ElementBounds,
        visibilityPercentage: Double = 1.0,
        confidence: Double = 1.0,
        source: ContextSource = .dom,
        tag: String? = nil,
        selector: String? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.bounds = bounds
        self.visibilityPercentage = visibilityPercentage
        self.confidence = confidence
        self.source = source
        self.tag = tag
        self.selector = selector
    }
}

/// Visual screenshot data captured via ScreenCaptureKit
public struct ScreenCaptureData: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let scaleFactor: Double
    public let displayID: UInt32?
    public let windowName: String?
    public let appName: String?
    public let pngBase64: String?

    public init(
        width: Int,
        height: Int,
        scaleFactor: Double = 2.0,
        displayID: UInt32? = nil,
        windowName: String? = nil,
        appName: String? = nil,
        pngBase64: String? = nil
    ) {
        self.width = width
        self.height = height
        self.scaleFactor = scaleFactor
        self.displayID = displayID
        self.windowName = windowName
        self.appName = appName
        self.pngBase64 = pngBase64
    }
}

/// Common Unified Context Model representing the user's visible screen state
public struct VisibleContext: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let source: ContextSource
    public let timestamp: Date
    public let viewport: ViewportInfo
    public let elements: [VisibleElement]
    public let screenshot: ScreenCaptureData?
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        source: ContextSource,
        timestamp: Date = Date(),
        viewport: ViewportInfo,
        elements: [VisibleElement] = [],
        screenshot: ScreenCaptureData? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.timestamp = timestamp
        self.viewport = viewport
        self.elements = elements
        self.screenshot = screenshot
        self.metadata = metadata
    }

    /// Sorted elements according to natural reading order (top-to-bottom, left-to-right)
    public var spatiallySortedElements: [VisibleElement] {
        elements.sorted { a, b in
            if abs(a.bounds.y - b.bounds.y) > 10 {
                return a.bounds.y < b.bounds.y
            }
            return a.bounds.x < b.bounds.x
        }
    }

    /// Convenience filtering for specific element types
    public func elements(ofType type: ElementType) -> [VisibleElement] {
        elements.filter { $0.type == type }
    }
}
