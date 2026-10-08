import AppKit

/// Provides read access to system pasteboard without altering contents
public final class SystemClipboardManager: ClipboardManagerProtocol, @unchecked Sendable {
    public init() {}

    public func hasContent() -> Bool {
        let pasteboard = NSPasteboard.general
        return (pasteboard.types?.count ?? 0) > 0
    }

    public func getString() -> String? {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string)
    }

    public func setString(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
}
