import Foundation
import Network

/// URLSession delegate that prevents automatic redirect following for GET probes
/// and binds connections to the physical WiFi interface to bypass TUN/VPN
private final class WiFiDirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = WiFiDirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // 不跟随重定向，直接返回 nil 停止
        completionHandler(nil)
    }
}

public final class DirectHTTPClient: Sendable {
    public let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        // 禁用 HTTP 代理
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false
        ]
        // 强制走 WiFi 物理接口，绕过 TUN/VPN
        self.session = URLSession(configuration: configuration, delegate: WiFiDirectDelegate.shared, delegateQueue: nil)
    }

    public func get(_ url: URL, timeout: TimeInterval = 8) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.assumesHTTP3Capable = false
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) HUSTCampusMenuBar/0.1",
            forHTTPHeaderField: "User-Agent"
        )
        return try await session.data(for: request)
    }

    public func postForm(
        _ url: URL,
        fields: [String: String],
        headers: [String: String] = [:],
        timeout: TimeInterval = 8
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.assumesHTTP3Capable = false
        request.httpBody = FormEncoding.encode(fields)
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) HUSTCampusMenuBar/0.1",
            forHTTPHeaderField: "User-Agent"
        )
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await session.data(for: request)
    }

    /// 使用 Network.framework 直接通过物理 WiFi 接口发送 HTTP 请求
    /// 这是绕过 TUN/VPN 的最可靠方式
    public func getRaw(_ url: URL, timeout: TimeInterval = 8) async throws -> (Data, HTTPURLResponse) {
        guard let host = url.host, let scheme = url.scheme else {
            throw AutologinError.invalidPortalURL(url.absoluteString)
        }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""

        let requestString = """
        GET \(path)\(query) HTTP/1.1\r
        Host: \(host)\r
        User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X) HUSTCampusMenuBar/0.1\r
        Accept: */*\r
        Connection: close\r
        \r

        """

        let data = try await sendRawTCP(host: host, port: UInt16(port), payload: Data(requestString.utf8), timeout: timeout)
        return try parseHTTPResponse(data)
    }

    public func postFormRaw(
        _ url: URL,
        fields: [String: String],
        headers: [String: String] = [:],
        timeout: TimeInterval = 8
    ) async throws -> (Data, HTTPURLResponse) {
        guard let host = url.host, let scheme = url.scheme else {
            throw AutologinError.invalidPortalURL(url.absoluteString)
        }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let body = FormEncoding.encode(fields)

        var headerLines = """
        POST \(path)\(query) HTTP/1.1\r
        Host: \(host)\r
        User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X) HUSTCampusMenuBar/0.1\r
        Accept: */*\r
        Content-Type: application/x-www-form-urlencoded; charset=UTF-8\r
        Content-Length: \(body.count)\r

        """
        for (key, value) in headers {
            headerLines += "\(key): \(value)\r\n"
        }
        headerLines += "Connection: close\r\n"
        headerLines += "\r\n"

        var payload = Data(headerLines.utf8)
        payload.append(body)

        let data = try await sendRawTCP(host: host, port: UInt16(port), payload: payload, timeout: timeout)
        return try parseHTTPResponse(data)
    }

    /// 通过 Network.framework 建立 TCP 连接，绑定到 WiFi 物理接口
    private func sendRawTCP(host: String, port: UInt16, payload: Data, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let parameters = NWParameters.tcp
            // 强制使用 WiFi 物理接口，绕过 utun (VPN/TUN)
            parameters.requiredInterfaceType = .wifi

            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)

            let queue = DispatchQueue(label: "com.jzy.HUSTCampusMenuBar.rawhttp")

            // 使用 class 包装可变状态以满足 Sendable 要求
            final class State: @unchecked Sendable {
                var completed = false
                var timeoutItem: DispatchWorkItem?
            }
            let state = State()

            let timeoutItem = DispatchWorkItem { [state] in
                guard !state.completed else { return }
                state.completed = true
                connection.cancel()
                continuation.resume(throwing: AutologinError.requestFailed("请求超时"))
            }
            state.timeoutItem = timeoutItem
            queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            connection.stateUpdateHandler = { [state] newState in
                switch newState {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { [state] error in
                        if let error = error {
                            guard !state.completed else { return }
                            state.completed = true
                            state.timeoutItem?.cancel()
                            connection.cancel()
                            continuation.resume(throwing: error)
                            return
                        }
                        self.receiveAll(connection: connection) { [state] result in
                            guard !state.completed else { return }
                            state.completed = true
                            state.timeoutItem?.cancel()
                            connection.cancel()
                            switch result {
                            case .success(let data):
                                continuation.resume(returning: data)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    })
                case .failed(let error):
                    guard !state.completed else { return }
                    state.completed = true
                    state.timeoutItem?.cancel()
                    connection.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func receiveAll(connection: NWConnection, accumulated: Data = Data(), completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
            var data = accumulated
            if let content = content {
                data.append(content)
            }
            if isComplete || error != nil {
                if data.isEmpty, let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(data))
                }
                return
            }
            self.receiveAll(connection: connection, accumulated: data, completion: completion)
        }
    }

    private func parseHTTPResponse(_ data: Data) throws -> (Data, HTTPURLResponse) {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw AutologinError.invalidResponse("无法解码响应")
        }
        guard let headerEnd = text.range(of: "\r\n\r\n") else {
            throw AutologinError.invalidResponse("无法解析 HTTP 响应头")
        }
        let headerPart = String(text[text.startIndex..<headerEnd.lowerBound])
        let bodyPart = String(text[headerEnd.upperBound...])
        let bodyData = bodyPart.data(using: .utf8) ?? Data()

        let lines = headerPart.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            throw AutologinError.invalidResponse("空响应")
        }
        // 解析 "HTTP/1.1 200 OK"
        let parts = statusLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, let statusCode = Int(parts[1]) else {
            throw AutologinError.invalidResponse("无法解析状态码: \(statusLine)")
        }

        var headerFields: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headerFields[key] = value
            }
        }

        let response = HTTPURLResponse(
            url: URL(string: "http://placeholder")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
        return (bodyData, response)
    }
}
