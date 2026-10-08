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
    private let port: UInt16

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
                ScreenSenseLogger.app.error("LocalBrowserBridge failed: \(error.localizedDescription)")
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
        lock.unlock()
        ScreenSenseLogger.app.info("Received DOM context update with \(context.elements.count) elements from \(context.viewport.pageTitle ?? "Webpage", privacy: .public)")
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readHTTPRequest(connection: connection)
    }

    private func readHTTPRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536 * 16) { [weak self] data, context, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }

            guard let requestString = String(data: data, encoding: .utf8) else {
                self.sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Invalid encoding\"}")
                return
            }

            self.processHTTPRequest(requestString: requestString, connection: connection)
        }
    }

    private func processHTTPRequest(requestString: String, connection: NWConnection) {
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

        // Handle CORS Preflight
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
                // Parse body after \r\n\r\n
                if let bodyRange = requestString.range(of: "\r\n\r\n") {
                    let body = String(requestString[bodyRange.upperBound...])
                    if let bodyData = body.data(using: .utf8) {
                        do {
                            let decoder = JSONDecoder()
                            decoder.dateDecodingStrategy = .iso8601
                            let decodedContext = try decoder.decode(VisibleContext.self, from: bodyData)
                            self.updateContext(decodedContext)
                            sendHTTPResponse(connection: connection, statusCode: 200, body: "{\"success\":true,\"receivedElements\":\(decodedContext.elements.count)}")
                            return
                        } catch {
                            ScreenSenseLogger.app.error("Failed to decode VisibleContext JSON: \(error.localizedDescription)")
                            sendHTTPResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Invalid JSON: \(error.localizedDescription)\"}")
                            return
                        }
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
        Access-Control-Allow-Headers: Content-Type, Authorization\r
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
        Access-Control-Allow-Headers: Content-Type, Authorization\r
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
