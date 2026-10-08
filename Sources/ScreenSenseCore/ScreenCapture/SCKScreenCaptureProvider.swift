import Foundation
import ScreenCaptureKit
import CoreGraphics
import AppKit

public enum ScreenCaptureError: LocalizedError, Sendable {
    case permissionDenied
    case noDisplaysFound
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required for ScreenCaptureKit. Please grant permission in System Settings -> Privacy & Security -> Screen Recording."
        case .noDisplaysFound:
            return "No active displays found for ScreenCaptureKit capture."
        case .captureFailed(let reason):
            return "ScreenCaptureKit capture failed: \(reason)"
        }
    }
}

/// ScreenCaptureKit-based screen and window capture provider
public final class SCKScreenCaptureProvider: ScreenCaptureProviderProtocol, @unchecked Sendable {
    public init() {}

    public func captureCurrentContext() async throws -> ScreenCaptureResult {
        // Verify screen recording permission
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            ScreenSenseLogger.app.error("Screen recording permission denied for ScreenCaptureKit")
            throw ScreenCaptureError.permissionDenied
        }

        ScreenSenseLogger.app.info("Starting on-demand ScreenCaptureKit screenshot capture...")

        do {
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let mainDisplay = shareableContent.displays.first else {
                ScreenSenseLogger.app.error("No active displays found in SCShareableContent")
                throw ScreenCaptureError.noDisplaysFound
            }

            // Find active frontmost window title / app if any
            let frontmostApp = NSWorkspace.shared.frontmostApplication
            let frontmostAppName = frontmostApp?.localizedName
            let activeWindow = shareableContent.windows.first(where: {
                $0.owningApplication?.bundleIdentifier == frontmostApp?.bundleIdentifier && $0.isOnScreen
            })

            let contentFilter = SCContentFilter(display: mainDisplay, excludingApplications: [], exceptingWindows: [])

            let config = SCStreamConfiguration()
            config.width = Int(mainDisplay.width * 2)
            config.height = Int(mainDisplay.height * 2)
            config.scalesToFit = false
            config.showsCursor = false
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: config)

            ScreenSenseLogger.app.info("ScreenCaptureKit screenshot captured successfully (\(cgImage.width)x\(cgImage.height))")

            return ScreenCaptureResult(
                image: cgImage,
                width: cgImage.width,
                height: cgImage.height,
                scaleFactor: 2.0,
                displayID: UInt32(mainDisplay.displayID),
                windowTitle: activeWindow?.title,
                applicationName: frontmostAppName,
                capturedAt: Date()
            )
        } catch let scError as ScreenCaptureError {
            throw scError
        } catch {
            ScreenSenseLogger.app.error("ScreenCaptureKit threw error: \(error.localizedDescription)")
            throw ScreenCaptureError.captureFailed(error.localizedDescription)
        }
    }
}
