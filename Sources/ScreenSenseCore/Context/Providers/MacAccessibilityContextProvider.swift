import Foundation
import AppKit
import ApplicationServices

/// Protocol for acquiring accessibility context from frontmost macOS applications
public protocol AccessibilityContextProviderProtocol: Sendable {
    func extractContext(for app: NSRunningApplication) async -> UnifiedContext?
}

/// Native macOS Accessibility context provider using Accessibility APIs (AXUIElement)
public struct MacAccessibilityContextProvider: AccessibilityContextProviderProtocol, Sendable {
    public init() {}

    public func extractContext(for app: NSRunningApplication) async -> UnifiedContext? {
        let appName = app.localizedName ?? "Application"
        let pid = app.processIdentifier

        let appElement = AXUIElementCreateApplication(pid)

        var windowTitle: String? = nil
        var focusedElementText: String? = nil
        var extractedElements: [VisibleElement] = []
        var textRegions: [TextRegion] = []

        // 1. Query focused window
        var focusedWindowValue: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)
        if windowResult == .success, let windowElement = focusedWindowValue {
            var titleValue: AnyObject?
            if AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXTitleAttribute as CFString, &titleValue) == .success,
               let titleStr = titleValue as? String {
                windowTitle = titleStr
            }

            // Traverse elements recursively in window
            traverseAXElement(
                element: windowElement as! AXUIElement,
                extracted: &extractedElements,
                textRegions: &textRegions,
                depth: 0,
                maxDepth: 6
            )
        }

        // 2. Query focused UI element directly
        var focusedElementValue: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue) == .success,
           let focusedEl = focusedElementValue {
            var val: AnyObject?
            if AXUIElementCopyAttributeValue(focusedEl as! AXUIElement, kAXValueAttribute as CFString, &val) == .success,
               let str = val as? String {
                focusedElementText = str
            }
        }

        let windowInfo = WindowInfo(
            title: windowTitle,
            appName: appName,
            bundleId: app.bundleIdentifier,
            bounds: nil
        )

        var metadata: [String: String] = [
            "pid": "\(pid)",
            "bundleId": app.bundleIdentifier ?? ""
        ]
        if let focused = focusedElementText {
            metadata["focusedText"] = focused
        }

        return UnifiedContext(
            source: .accessibility,
            applicationName: appName,
            windowInfo: windowInfo,
            viewport: nil,
            elements: extractedElements,
            largeTextRegions: textRegions,
            activeElementId: nil,
            metadata: metadata
        )
    }

    private func traverseAXElement(
        element: AXUIElement,
        extracted: inout [VisibleElement],
        textRegions: inout [TextRegion],
        depth: Int,
        maxDepth: Int
    ) {
        guard depth <= maxDepth else { return }

        var roleValue: AnyObject?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = (roleValue as? String) ?? ""

        var valueObj: AnyObject?
        _ = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj)
        let textValue = (valueObj as? String) ?? ""

        var titleObj: AnyObject?
        _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleObj)
        let titleValue = (titleObj as? String) ?? ""

        let effectiveText = !textValue.isEmpty ? textValue : titleValue

        // Map AX role to ElementType
        var elemType: ElementType = .genericText
        if role == kAXButtonRole as String {
            elemType = .button
        } else if role == kAXStaticTextRole as String {
            elemType = .paragraph
        } else if role == kAXHeadingRole as String {
            elemType = .heading
        } else if role == kAXTextAreaRole as String || role == kAXTextFieldRole as String {
            elemType = .input
        }

        if !effectiveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let el = VisibleElement(
                id: "ax-\(extracted.count + 1)",
                type: elemType,
                text: effectiveText,
                bounds: ElementBounds(x: 0, y: Double(depth * 30), width: 500, height: 30),
                tag: role
            )
            extracted.append(el)

            if effectiveText.count > 40 {
                textRegions.append(TextRegion(id: el.id, text: effectiveText, role: role, bounds: el.bounds))
            }
        }

        // Traverse children
        var childrenValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let childrenArray = childrenValue as? [AXUIElement] {
            for child in childrenArray.prefix(25) {
                traverseAXElement(
                    element: child,
                    extracted: &extracted,
                    textRegions: &textRegions,
                    depth: depth + 1,
                    maxDepth: maxDepth
                )
            }
        }
    }
}
