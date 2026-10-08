import Foundation

/// Context Fusion Engine combining DOM and ScreenCaptureKit context sources
public final class ContextFusion: ContextFusionProtocol, Sendable {
    public init() {}

    public func fuse(dom: VisibleContext?, screen: ScreenCaptureResult?) -> VisibleContext {
        let screenshotData = screen?.toCaptureData()

        if let dom = dom {
            // Merge DOM context with visual screen capture confirmation
            var metadata = dom.metadata
            metadata["fusion_type"] = "dom_plus_screen"
            metadata["dom_element_count"] = "\(dom.elements.count)"
            if let screen = screen {
                metadata["screen_resolution"] = "\(screen.width)x\(screen.height)"
                if let appName = screen.applicationName {
                    metadata["active_app"] = appName
                }
            }

            return VisibleContext(
                id: UUID().uuidString,
                source: .unified,
                timestamp: Date(),
                viewport: dom.viewport,
                elements: dom.spatiallySortedElements,
                screenshot: screenshotData,
                metadata: metadata
            )
        } else if let screen = screen {
            // Visual screen capture only (non-browser application or browser extension not active)
            var metadata: [String: String] = [
                "fusion_type": "screen_only",
                "screen_resolution": "\(screen.width)x\(screen.height)"
            ]
            if let appName = screen.applicationName {
                metadata["active_app"] = appName
            }
            if let winTitle = screen.windowTitle {
                metadata["window_title"] = winTitle
            }

            let fallbackViewport = ViewportInfo(
                width: Double(screen.width) / screen.scaleFactor,
                height: Double(screen.height) / screen.scaleFactor,
                scrollX: 0,
                scrollY: 0,
                devicePixelRatio: screen.scaleFactor,
                pageTitle: screen.windowTitle,
                url: nil
            )

            return VisibleContext(
                id: UUID().uuidString,
                source: .screen,
                timestamp: Date(),
                viewport: fallbackViewport,
                elements: [], // OCR / Vision can populate in future phases
                screenshot: screenshotData,
                metadata: metadata
            )
        } else {
            // Empty fallback
            return VisibleContext(
                id: UUID().uuidString,
                source: .screen,
                timestamp: Date(),
                viewport: ViewportInfo(width: 0, height: 0),
                elements: [],
                screenshot: nil,
                metadata: ["fusion_type": "none"]
            )
        }
    }
}
