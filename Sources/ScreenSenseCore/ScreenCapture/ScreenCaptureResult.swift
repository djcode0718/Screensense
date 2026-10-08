import Foundation
import CoreGraphics
import AppKit

public struct ScreenCaptureResult: Sendable {
    public let image: CGImage
    public let width: Int
    public let height: Int
    public let scaleFactor: Double
    public let displayID: UInt32?
    public let windowTitle: String?
    public let applicationName: String?
    public let capturedAt: Date

    public init(
        image: CGImage,
        width: Int,
        height: Int,
        scaleFactor: Double = 2.0,
        displayID: UInt32? = nil,
        windowTitle: String? = nil,
        applicationName: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.image = image
        self.width = width
        self.height = height
        self.scaleFactor = scaleFactor
        self.displayID = displayID
        self.windowTitle = windowTitle
        self.applicationName = applicationName
        self.capturedAt = capturedAt
    }

    /// Converts CGImage to PNG Data
    public func pngData() -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    /// Converts to base64 string for JSON payload transfer
    public func pngBase64() -> String? {
        pngData()?.base64EncodedString()
    }

    /// Converts to ScreenCaptureData model
    public func toCaptureData() -> ScreenCaptureData {
        ScreenCaptureData(
            width: width,
            height: height,
            scaleFactor: scaleFactor,
            displayID: displayID,
            windowName: windowTitle,
            appName: applicationName,
            pngBase64: pngBase64()
        )
    }
}
