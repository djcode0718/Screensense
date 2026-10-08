import Foundation
import CoreGraphics

/// Freshness lifecycle state of a context snapshot
public enum FreshnessState: String, Codable, Equatable, Sendable {
    case ready = "ready"
    case fresh = "fresh"
    case stale = "stale"
    case expired = "expired"
}

/// Metadata about the frontmost window and application
public struct WindowInfo: Codable, Equatable, Sendable {
    public let title: String?
    public let appName: String
    public let bundleId: String?
    public let bounds: ElementBounds?

    public init(
        title: String?,
        appName: String,
        bundleId: String? = nil,
        bounds: ElementBounds? = nil
    ) {
        self.title = title
        self.appName = appName
        self.bundleId = bundleId
        self.bounds = bounds
    }
}

/// Region of large text context (documents, message threads, editors)
public struct TextRegion: Codable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let role: String?
    public let bounds: ElementBounds?
    public let children: [TextRegion]?

    public init(
        id: String,
        text: String,
        role: String? = nil,
        bounds: ElementBounds? = nil,
        children: [TextRegion]? = nil
    ) {
        self.id = id
        self.text = text
        self.role = role
        self.bounds = bounds
        self.children = children
    }
}

/// Universal unified context model representing active screen, DOM, or accessibility state
public struct UnifiedContext: Codable, Equatable, Sendable {
    public let id: String
    public let source: ContextSource
    public let timestamp: Date
    public let applicationName: String
    public let windowInfo: WindowInfo?
    public let viewport: ViewportInfo?
    public let elements: [VisibleElement]
    public let largeTextRegions: [TextRegion]
    public let activeElementId: String?
    public let pointer: PointerContext?
    public let selection: SelectionContext?
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        source: ContextSource,
        timestamp: Date = Date(),
        applicationName: String,
        windowInfo: WindowInfo? = nil,
        viewport: ViewportInfo? = nil,
        elements: [VisibleElement] = [],
        largeTextRegions: [TextRegion] = [],
        activeElementId: String? = nil,
        pointer: PointerContext? = nil,
        selection: SelectionContext? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.timestamp = timestamp
        self.applicationName = applicationName
        self.windowInfo = windowInfo
        self.viewport = viewport
        self.elements = elements
        self.largeTextRegions = largeTextRegions
        self.activeElementId = activeElementId
        self.pointer = pointer
        self.selection = selection
        self.metadata = metadata
    }

    /// Elements sorted in natural visual reading order (top-to-bottom, left-to-right)
    public var spatiallySortedElements: [VisibleElement] {
        elements.sorted { a, b in
            let yDiff = a.bounds.y - b.bounds.y
            if abs(yDiff) > 12 {
                return yDiff < 0
            }
            return a.bounds.x < b.bounds.x
        }
    }

    /// Evaluates freshness based on age (fresh under 10 seconds, stale up to 60s)
    public var freshnessState: FreshnessState {
        let age = Date().timeIntervalSince(timestamp)
        if age < 15.0 {
            return .fresh
        } else if age < 60.0 {
            return .stale
        } else {
            return .expired
        }
    }

    /// Evaluates the user-facing active tab title or document title
    public var activeTabTitle: String {
        let isChrome = applicationName.contains("Chrome") || applicationName.contains("Chromium")
        if isChrome {
            if let pageTitle = viewport?.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !pageTitle.isEmpty {
                return pageTitle
            }
            if let metaTitle = metadata["page_title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !metaTitle.isEmpty {
                return metaTitle
            }
            if let winTitle = windowInfo?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !winTitle.isEmpty, winTitle != "Google Chrome", winTitle != "Chrome", winTitle != "Active Window" {
                return winTitle
            }
            if let urlStr = viewport?.url, let url = URL(string: urlStr), let host = url.host {
                let path = url.path.count > 1 ? url.path : ""
                return "\(host)\(path)"
            }
            return "—"
        } else {
            if let winTitle = windowInfo?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !winTitle.isEmpty, winTitle != applicationName, winTitle != "Active Window" {
                return winTitle
            }
            return "—"
        }
    }

    /// Creates a UnifiedContext from a browser DOM VisibleContext
    public static func fromDOMContext(_ dom: VisibleContext, appName: String = "Google Chrome") -> UnifiedContext {
        let windowTitle = dom.viewport.pageTitle ?? "Web Page"
        let windowInfo = WindowInfo(
            title: windowTitle,
            appName: appName,
            bundleId: "com.google.Chrome",
            bounds: ElementBounds(x: 0, y: 0, width: dom.viewport.width, height: dom.viewport.height)
        )

        // Generate text regions from paragraphs and headings
        let textRegions = dom.elements.filter { $0.type == .paragraph || $0.type == .heading || $0.type == .genericText }.map {
            TextRegion(id: $0.id, text: $0.text, role: $0.type.rawValue, bounds: $0.bounds)
        }

        return UnifiedContext(
            id: dom.id,
            source: .dom,
            timestamp: dom.timestamp,
            applicationName: appName,
            windowInfo: windowInfo,
            viewport: dom.viewport,
            elements: dom.elements,
            largeTextRegions: textRegions,
            activeElementId: nil,
            pointer: dom.pointer,
            selection: dom.selection,
            metadata: dom.metadata
        )
    }
}
