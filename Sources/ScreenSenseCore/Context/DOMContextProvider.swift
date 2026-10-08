import Foundation

/// Provides DOM context retrieved via the local browser bridge
public final class DOMContextProvider: DOMContextProviderProtocol, @unchecked Sendable {
    private let bridge: BrowserBridgeProtocol

    public init(bridge: BrowserBridgeProtocol) {
        self.bridge = bridge
    }

    public func fetchCurrentDOMContext() async throws -> VisibleContext? {
        return bridge.latestDOMContext
    }
}
