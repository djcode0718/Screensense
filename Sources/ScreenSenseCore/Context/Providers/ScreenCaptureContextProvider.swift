import Foundation
import ScreenCaptureKit
import Vision
import AppKit

/// Protocol for acquiring visual and OCR screen capture context
public protocol ScreenCaptureContextProviderProtocol: Sendable {
    func extractContext(for app: NSRunningApplication?) async -> UnifiedContext?
}

/// Fallback Context Provider using ScreenCaptureKit snapshot + Vision OCR recognition
public struct ScreenCaptureContextProvider: ScreenCaptureContextProviderProtocol, Sendable {
    private let captureProvider: ScreenCaptureProviderProtocol

    public init(captureProvider: ScreenCaptureProviderProtocol = SCKScreenCaptureProvider()) {
        self.captureProvider = captureProvider
    }

    public func extractContext(for app: NSRunningApplication?) async -> UnifiedContext? {
        let appName = app?.localizedName ?? "Screen"

        do {
            let captureResult = try await captureProvider.captureCurrentContext()
            let cgImage = captureResult.image

            var recognizedElements: [VisibleElement] = []
            var textRegions: [TextRegion] = []

            // Vision OCR Request
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            if let observations = request.results {
                let imgWidth = Double(cgImage.width)
                let imgHeight = Double(cgImage.height)

                for (idx, observation) in observations.enumerated() {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }
                    let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }

                    // Vision coordinates are normalized (0..1) with origin at bottom-left
                    let box = observation.boundingBox
                    let x = box.origin.x * imgWidth
                    let y = (1.0 - box.origin.y - box.size.height) * imgHeight
                    let width = box.size.width * imgWidth
                    let height = box.size.height * imgHeight

                    let bounds = ElementBounds(x: x, y: y, width: width, height: height)
                    let el = VisibleElement(
                        id: "ocr-\(idx + 1)",
                        type: .genericText,
                        text: text,
                        bounds: bounds,
                        confidence: Double(topCandidate.confidence),
                        source: .ocr,
                        tag: "ocr"
                    )
                    recognizedElements.append(el)
                }
            }

            // Sort recognized elements in spatial reading order (top-to-bottom, left-to-right)
            recognizedElements.sort { a, b in
                let yDiff = a.bounds.y - b.bounds.y
                if abs(yDiff) > 12 {
                    return yDiff < 0
                }
                return a.bounds.x < b.bounds.x
            }

            // Group adjacent lines into logical multi-line TextRegions (e.g. paragraphs, chat messages)
            var currentGroup: [VisibleElement] = []
            for element in recognizedElements {
                if currentGroup.isEmpty {
                    currentGroup.append(element)
                } else {
                    let prev = currentGroup.last!
                    let verticalGap = element.bounds.y - (prev.bounds.y + prev.bounds.height)
                    let horizontalAligned = abs(element.bounds.x - prev.bounds.x) < 80 || (element.bounds.x < prev.bounds.x + prev.bounds.width && element.bounds.x + element.bounds.width > prev.bounds.x)

                    if verticalGap >= -10 && verticalGap < max(35.0, prev.bounds.height * 2.0) && horizontalAligned {
                        currentGroup.append(element)
                    } else {
                        // Create TextRegion from currentGroup
                        if let region = Self.buildTextRegion(from: currentGroup, index: textRegions.count + 1) {
                            textRegions.append(region)
                        }
                        currentGroup = [element]
                    }
                }
            }
            if !currentGroup.isEmpty, let region = Self.buildTextRegion(from: currentGroup, index: textRegions.count + 1) {
                textRegions.append(region)
            }

            let windowInfo = WindowInfo(
                title: captureResult.windowTitle ?? appName,
                appName: appName,
                bundleId: app?.bundleIdentifier,
                bounds: nil
            )

            return UnifiedContext(
                source: .ocr,
                applicationName: appName,
                windowInfo: windowInfo,
                viewport: ViewportInfo(width: Double(cgImage.width), height: Double(cgImage.height)),
                elements: recognizedElements,
                largeTextRegions: textRegions,
                activeElementId: nil,
                metadata: [
                    "ocrElementCount": "\(recognizedElements.count)",
                    "textRegionCount": "\(textRegions.count)"
                ]
            )
        } catch {
            ScreenSenseLogger.context.error("ScreenCaptureContextProvider OCR failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func buildTextRegion(from elements: [VisibleElement], index: Int) -> TextRegion? {
        guard !elements.isEmpty else { return nil }
        let combinedText = elements.map { $0.text }.joined(separator: "\n")
        let minX = elements.map { $0.bounds.x }.min() ?? 0
        let minY = elements.map { $0.bounds.y }.min() ?? 0
        let maxX = elements.map { $0.bounds.x + $0.bounds.width }.max() ?? minX
        let maxY = elements.map { $0.bounds.y + $0.bounds.height }.max() ?? minY

        let regionBounds = ElementBounds(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return TextRegion(
            id: "region-\(index)",
            text: combinedText,
            role: elements.count > 1 ? "paragraph" : "line",
            bounds: regionBounds
        )
    }
}
