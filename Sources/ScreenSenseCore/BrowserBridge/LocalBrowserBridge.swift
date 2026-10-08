import Foundation
import Network

/// Native macOS HTTP bridge listening on localhost for Chrome Extension DOM context
public final class LocalBrowserBridge: BrowserBridgeProtocol, @unchecked Sendable {
    public static let defaultPort: UInt16 = 41920

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.screensense.browserbridge", qos: .userInitiated)
    private let lock = NSLock()
    private var _latestDOMContext: VisibleContext?
    private var _lastConnectedAt: Date?
    private var _onContextReceived: (@Sendable (VisibleContext) -> Void)?
    private let port: UInt16

    public var onContextReceived: (@Sendable (VisibleContext) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onContextReceived
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _onContextReceived = newValue
        }
    }

    public var latestDOMContext: VisibleContext? {
        lock.lock()
        defer { lock.unlock() }
        return _latestDOMContext
    }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let last = _lastConnectedAt else { return false }
        return Date().timeIntervalSince(last) < 60 // Connected within last 60 seconds
    }

    public init(port: UInt16 = LocalBrowserBridge.defaultPort) {
        self.port = port
    }

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard listener == nil else { return }

        let params = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 41920)!
        let newListener = try NWListener(using: params, on: nwPort)

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleIncomingConnection(connection)
        }

        newListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ScreenSenseLogger.app.info("LocalBrowserBridge listening on 127.0.0.1:\(self.port)")
            case .failed(let error):
                ScreenSenseLogger.app.error("LocalBrowserBridge failed on port \(self.port): \(error.localizedDescription)")
            case .cancelled:
                ScreenSenseLogger.app.info("LocalBrowserBridge cancelled")
            default:
                break
            }
        }

        newListener.start(queue: queue)
        self.listener = newListener
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        listener?.cancel()
        listener = nil
        ScreenSenseLogger.app.info("LocalBrowserBridge stopped")
    }

    public func updateContext(_ context: VisibleContext) {
        lock.lock()
        self._latestDOMContext = context
        self._lastConnectedAt = Date()
        let handler = self._onContextReceived
        lock.unlock()

        let tabId = context.metadata["tab_id"] ?? "unknown"
        let windowId = context.metadata["window_id"] ?? "unknown"
        let pageTitle = context.viewport.pageTitle ?? "Webpage"
        let url = context.viewport.url ?? "unknown"

        ScreenSenseLogger.app.info("[SS-TAB-SYNC] ScreenSense LocalBrowserBridge.updateContext() received \(context.elements.count) elements from tabId=\(tabId, privacy: .public) windowId=\(windowId, privacy: .public) '\(pageTitle, privacy: .public)' (url: \(url, privacy: .public)) timestamp: \(context.timestamp, privacy: .public)")
        ScreenSenseLogger.app.info("[SS-VIEWPORT-SYNC] Swift context received scrollY=\(Int(context.viewport.scrollY)) elements=\(context.elements.count)")
        handler?(context)
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        let buffer = Data()
        accumulateHTTPData(connection: connection, buffer: buffer)
    }

    private func accumulateHTTPData(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536 * 16) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }

            var newBuffer = buffer
            if let data = data, !data.isEmpty {
                newBuffer.append(data)
            }

            // Check if headers have been fully received (\r\n\r\n)
            if let headerEndRange = newBuffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
                let headerData = newBuffer.subdata(in: 0..<headerEndRange.lowerBound)
                let headerString = String(data: headerData, encoding: .utf8) ?? ""

                // Extract Content-Length if present
                var expectedContentLength = 0
                for line in headerString.components(separatedBy: "\r\n") {
                    let lower = line.lowercased()
                    if lower.hasPrefix("content-length:") {
                        let parts = line.components(separatedBy: ":")
                        if parts.count >= 2 {
                            expectedContentLength = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                        }
                    }
                }

                let bodyReceivedLength = newBuffer.count - headerEndRange.upperBound

                if bodyReceivedLength >= expectedContentLength || isComplete {
                    self.processFullHTTPRequest(data: newBuffer, connection: connection)
                    return
                }
            }

            if isComplete {
                if !newBuffer.isEmpty {
                    self.processFullHTTPRequest(data: newBuffer, connection: connection)
                } else {
                    connection.cancel()
                }
                return
            }

            if let error = error {
                ScreenSenseLogger.app.error("Connection receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            // Continue reading next chunk
            self.accumulateHTTPData(connection: connection, buffer: newBuffer)
        }
    }

    private func processFullHTTPRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Invalid encoding\"}")
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Bad request\"}")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Bad request\"}")
            return
        }

        let method = parts[0].uppercased()
        let path = parts[1]

        ScreenSenseLogger.app.info("Incoming HTTP \(method, privacy: .public) \(path, privacy: .public)")

        // Handle CORS Preflight (OPTIONS)
        if method == "OPTIONS" {
            sendCORSPreflightResponse(connection: connection)
            return
        }

        if path == "/api/status" && method == "GET" {
            let statusJson = """
            {"status":"running","bridge":"LocalBrowserBridge","port":\(self.port)}
            """
            sendHTTPResponse(connection: connection, statusCode: 200, body: statusJson)
            return
        }

        if path == "/api/context" {
            if method == "GET" {
                if let current = self.latestDOMContext {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    if let encoded = try? encoder.encode(current), let json = String(data: encoded, encoding: .utf8) {
                        sendHTTPResponse(connection: connection, statusCode: 200, body: json)
                    } else {
                        sendHTTPResponse(connection: connection, statusCode: 500, body: "{\"error\":\"Encoding error\"}")
                    }
                } else {
                    sendHTTPResponse(connection: connection, statusCode: 404, body: "{\"message\":\"No DOM context captured yet\"}")
                }
                return
            } else if method == "POST" {
                if let headerEndRange = data.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
                    let headerData = data.subdata(in: 0..<headerEndRange.lowerBound)
                    let headerString = String(data: headerData, encoding: .utf8) ?? ""

                    // Extract Content-Length from header
                    var contentLengthHeader = "none"
                    for hLine in headerString.components(separatedBy: "\r\n") {
                        if hLine.lowercased().hasPrefix("content-length:") {
                            contentLengthHeader = hLine
                        }
                    }

                    let bodyData = data.subdata(in: headerEndRange.upperBound..<data.count)
                    let bodySnippet = String(data: bodyData.prefix(1000), encoding: .utf8) ?? "<non-utf8 bytes>"

                    ScreenSenseLogger.app.info("[DIAGNOSTIC] HTTP POST /api/context: \(contentLengthHeader, privacy: .public), BodyByteCount=\(bodyData.count), Snippet=\(bodySnippet, privacy: .public)")

                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .custom { d in
                            let container = try d.singleValueContainer()
                            let dateStr = try container.decode(String.self)
                            let iso8601WithMillis = ISO8601DateFormatter()
                            iso8601WithMillis.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            if let date = iso8601WithMillis.date(from: dateStr) {
                                return date
                            }
                            let iso8601Standard = ISO8601DateFormatter()
                            iso8601Standard.formatOptions = [.withInternetDateTime]
                            if let date = iso8601Standard.date(from: dateStr) {
                                return date
                            }
                            throw DecodingError.dataCorruptedError(
                                in: container,
                                debugDescription: "Expected date string to be ISO8601-formatted (with or without fractional seconds), received: \(dateStr)"
                            )
                        }

                        let decodedContext = try decoder.decode(VisibleContext.self, from: bodyData)
                        self.updateContext(decodedContext)
                        ScreenSenseLogger.app.info("[DIAGNOSTIC] Successfully decoded VisibleContext with \(decodedContext.elements.count) elements.")
                        sendHTTPResponse(connection: connection, statusCode: 200, body: "{\"success\":true,\"receivedElements\":\(decodedContext.elements.count)}")
                        return
                    } catch let decErr as DecodingError {
                        let diagError: String
                        switch decErr {
                        case .keyNotFound(let key, let context):
                            diagError = "keyNotFound: '\(key.stringValue)' at codingPath: \(context.codingPath.map(\.stringValue)), debug: \(context.debugDescription)"
                        case .typeMismatch(let type, let context):
                            diagError = "typeMismatch for type '\(type)' at codingPath: \(context.codingPath.map(\.stringValue)), debug: \(context.debugDescription)"
                        case .valueNotFound(let type, let context):
                            diagError = "valueNotFound for type '\(type)' at codingPath: \(context.codingPath.map(\.stringValue)), debug: \(context.debugDescription)"
                        case .dataCorrupted(let context):
                            diagError = "dataCorrupted at codingPath: \(context.codingPath.map(\.stringValue)), debug: \(context.debugDescription)"
                        @unknown default:
                            diagError = decErr.localizedDescription
                        }

                        ScreenSenseLogger.app.error("[DIAGNOSTIC] DecodingError: \(diagError, privacy: .public)")
                        sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\":\"DecodingError: \(diagError)\"}")
                        return
                    } catch {
                        ScreenSenseLogger.app.error("[DIAGNOSTIC] General JSON Decode Error: \(error.localizedDescription, privacy: .public)")
                        sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Invalid JSON: \(error.localizedDescription)\"}")
                        return
                    }
                }
            }
        }

        sendHTTPResponse(connection: connection, statusCode: 404, body: "{\"error\":\"Not Found\"}")
    }

    private func sendCORSPreflightResponse(connection: NWConnection) {
        let headers = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Authorization, Accept\r
        Access-Control-Max-Age: 86400\r
        Content-Length: 0\r
        Connection: close\r
        \r\n
        """
        if let headerData = headers.data(using: .utf8) {
            connection.send(content: headerData, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }

    private func sendHTTPResponse(connection: NWConnection, statusCode: Int, body: String) {
        let statusMessage = (statusCode == 200) ? "OK" : (statusCode == 404 ? "Not Found" : (statusCode == 204 ? "No Content" : "Error"))
        let bodyData = body.data(using: .utf8) ?? Data()
        let headers = """
        HTTP/1.1 \(statusCode) \(statusMessage)\r
        Content-Type: application/json; charset=utf-8\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Authorization, Accept\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r\n
        """

        var responseData = headers.data(using: .utf8) ?? Data()
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
