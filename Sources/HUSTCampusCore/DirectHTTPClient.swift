import Foundation
#if canImport(Network)
import Network
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: - Cross-platform HTTP Client

public final class DirectHTTPClient: Sendable {
    public let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        #if os(macOS)
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false
        ]
        self.session = URLSession(configuration: configuration, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
        #else
        self.session = URLSession(configuration: configuration, delegate: NoRedirectDelegate.shared, delegateQueue: nil)
        #endif
    }

    public func get(_ url: URL, timeout: TimeInterval = 8) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(
            "Mozilla/5.0 (compatible; HUSTCampusAutologin/0.1)",
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
        request.httpBody = FormEncoding.encode(fields)
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (compatible; HUSTCampusAutologin/0.1)",
            forHTTPHeaderField: "User-Agent"
        )
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await session.data(for: request)
    }

    // MARK: - Raw TCP methods (cross-platform)

    /// 发送 HTTP GET 请求，macOS 上绑定 WiFi 物理接口绕过 TUN，Linux 上直连
    public func getRaw(_ url: URL, timeout: TimeInterval = 8) async throws -> (Data, HTTPURLResponse) {
        guard let host = url.host, let scheme = url.scheme else {
            throw AutologinError.invalidPortalURL(url.absoluteString)
        }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""

        let requestString = "GET \(path)\(query) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: Mozilla/5.0 (compatible; HUSTCampusAutologin/0.1)\r\nAccept: */*\r\nConnection: close\r\n\r\n"

        let data = try await sendRawTCP(host: host, port: UInt16(port), payload: Data(requestString.utf8), timeout: timeout)
        return try parseHTTPResponse(data, originalURL: url)
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

        var headerStr = "POST \(path)\(query) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: Mozilla/5.0 (compatible; HUSTCampusAutologin/0.1)\r\nAccept: */*\r\nContent-Type: application/x-www-form-urlencoded; charset=UTF-8\r\nContent-Length: \(body.count)\r\n"
        for (key, value) in headers {
            headerStr += "\(key): \(value)\r\n"
        }
        headerStr += "Connection: close\r\n\r\n"

        var payload = Data(headerStr.utf8)
        payload.append(body)

        let data = try await sendRawTCP(host: host, port: UInt16(port), payload: payload, timeout: timeout)
        return try parseHTTPResponse(data, originalURL: url)
    }

    // MARK: - Platform-specific raw TCP

    #if canImport(Network)
    private func sendRawTCP(host: String, port: UInt16, payload: Data, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .wifi

            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
            let queue = DispatchQueue(label: "com.jzy.HUSTCampus.rawhttp")

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
            if let content = content { data.append(content) }
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

    #else
    // Linux: 使用 POSIX socket 直连
    private func sendRawTCP(host: String, port: UInt16, payload: Data, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let data = try Self.posixTCPRequest(host: host, port: port, payload: payload, timeout: timeout)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func posixTCPRequest(host: String, port: UInt16, payload: Data, timeout: TimeInterval) throws -> Data {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = Int32(SOCK_STREAM)
        hints.ai_protocol = Int32(IPPROTO_TCP)

        var result: UnsafeMutablePointer<addrinfo>?
        let portStr = String(port)
        let status = getaddrinfo(host, portStr, &hints, &result)
        guard status == 0, let addrInfo = result else {
            throw AutologinError.requestFailed("DNS 解析失败: \(host)")
        }
        defer { freeaddrinfo(result) }

        let sock = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
        guard sock >= 0 else {
            throw AutologinError.requestFailed("创建 socket 失败")
        }
        defer { close(sock) }

        // 设置超时
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let connectResult = connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)
        guard connectResult == 0 else {
            throw AutologinError.requestFailed("连接失败: \(host):\(port)")
        }

        // 发送
        let sent = payload.withUnsafeBytes { buffer in
            send(sock, buffer.baseAddress, buffer.count, 0)
        }
        guard sent == payload.count else {
            throw AutologinError.requestFailed("发送数据失败")
        }

        // 接收
        var responseData = Data()
        let bufferSize = 65536
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while true {
            let received = recv(sock, &buffer, bufferSize, 0)
            if received <= 0 { break }
            responseData.append(contentsOf: buffer[0..<received])
        }

        guard !responseData.isEmpty else {
            throw AutologinError.requestFailed("服务器无响应")
        }
        return responseData
    }
    #endif

    // MARK: - HTTP Response Parser

    private func parseHTTPResponse(_ data: Data, originalURL: URL) throws -> (Data, HTTPURLResponse) {
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
            url: originalURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
        return (bodyData, response)
    }
}

// MARK: - No-redirect delegate

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
