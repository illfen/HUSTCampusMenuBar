import Foundation

public final class EportalClient: Sendable {
    private let client: DirectHTTPClient

    public init(client: DirectHTTPClient) {
        self.client = client
    }

    public func login(username: String, password: String, portalURL: URL, timeout: TimeInterval = 8) async throws -> LoginResult {
        let parsed = try PortalURL.parse(portalURL)
        let pageInfo = try? await fetchPageInfo(baseURL: parsed.baseURL, queryString: parsed.queryString, timeout: timeout)
        var attempts: [(password: String, encrypted: String, label: String)] = []

        if
            let pageInfo,
            pageInfo.passwordEncrypt,
            let exponent = pageInfo.publicKeyExponent,
            let modulus = pageInfo.publicKeyModulus
        {
            if let encrypted = try? RSAEncryptor.portalEncrypt(
                password: password,
                mac: parsed.mac,
                exponentHex: exponent,
                modulusHex: modulus
            ) {
                attempts.append((encrypted, "true", "pageInfo"))
            }
        } else if pageInfo?.passwordEncrypt == false {
            attempts.append((password, "false", "plain"))
        }

        attempts.append((
            RSAEncryptor.legacyEncrypt(password: password, mac: parsed.mac),
            "true",
            "legacy"
        ))

        var last = LoginResult(success: false, message: "尚未尝试登录")
        for attempt in deduplicate(attempts) {
            let result = try await submitLogin(
                username: username,
                password: attempt.password,
                passwordEncrypt: attempt.encrypted,
                parsed: parsed,
                timeout: timeout
            )
            if result.success {
                return result
            }
            last = LoginResult(success: false, message: "\(attempt.label): \(result.message)", userIndex: result.userIndex)
        }
        return last
    }

    public func login(username: String, password: String, queryString: String, baseURL: URL, timeout: TimeInterval = 8) async throws -> LoginResult {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = baseURL.path.rstrip("/") + "/index.jsp"
        components?.percentEncodedQuery = queryString
        guard let portalURL = components?.url else {
            throw AutologinError.invalidPortalURL(baseURL.absoluteString)
        }
        return try await login(username: username, password: password, portalURL: portalURL, timeout: timeout)
    }

    private func fetchPageInfo(baseURL: URL, queryString: String, timeout: TimeInterval) async throws -> PageInfo {
        let url = interfaceURL(baseURL: baseURL, method: "pageInfo")
        let (data, response) = try await client.postFormRaw(
            url,
            fields: ["queryString": queryString],
            timeout: timeout
        )
        let statusCode = response.statusCode
        let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? "(non-utf8)"
        debugLog("pageInfo POST \(url.absoluteString) -> \(statusCode), body=\(bodyStr)")

        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw AutologinError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return PageInfo(json: json)
    }

    private func submitLogin(
        username: String,
        password: String,
        passwordEncrypt: String,
        parsed: ParsedPortalURL,
        timeout: TimeInterval
    ) async throws -> LoginResult {
        let url = interfaceURL(baseURL: parsed.baseURL, method: "login")
        let origin = parsed.baseURL.absoluteString.components(separatedBy: "/eportal").first ?? parsed.baseURL.absoluteString
        let referer = parsed.baseURL.appendingPathComponent("index.jsp").absoluteString + "?" + parsed.queryString
        let fields = [
            "userId": username,
            "password": password,
            "service": "",
            "queryString": parsed.queryString,
            "operatorPwd": "",
            "operatorUserId": "",
            "validcode": "",
            "passwordEncrypt": passwordEncrypt
        ]

        let (data, response) = try await client.postFormRaw(
            url,
            fields: fields,
            headers: [
                "Origin": origin,
                "Referer": referer
            ],
            timeout: timeout
        )

        // 诊断日志
        let statusCode = response.statusCode
        let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? "(non-utf8, \(data.count) bytes)"
        debugLog("login POST \(url.absoluteString) -> \(statusCode), body=\(bodyStr)")

        guard !data.isEmpty else {
            return LoginResult(success: false, message: "认证服务返回空响应")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw AutologinError.invalidResponse(String(data: data, encoding: .utf8) ?? "")
        }
        let success = String(describing: json["result"] ?? "").lowercased() == "success"
        let message = decodeMessage(json["message"] ?? "")
        let userIndex = json["userIndex"].map { String(describing: $0) }
        return LoginResult(success: success, message: message, userIndex: userIndex)
    }

    private func interfaceURL(baseURL: URL, method: String) -> URL {
        // 确保 baseURL 以 / 结尾，这样相对路径才能正确拼接
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL : baseURL.appendingPathComponent("")
        return URL(string: "InterFace.do?method=\(method)", relativeTo: base)!.absoluteURL
    }

    private func deduplicate(_ attempts: [(password: String, encrypted: String, label: String)]) -> [(password: String, encrypted: String, label: String)] {
        var seen = Set<String>()
        return attempts.filter { attempt in
            let key = "\(attempt.encrypted):\(attempt.password)"
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func decodeMessage(_ value: Any) -> String {
        let message = String(describing: value)
        guard let repaired = message.data(using: .isoLatin1).flatMap({ String(data: $0, encoding: .utf8) }) else {
            return message
        }
        if repaired.contains(where: { "\u{4e00}" <= $0 && $0 <= "\u{9fff}" }) {
            return repaired
        }
        return message
    }

    private func debugLog(_ message: String) {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/HUSTCampusMenuBar", isDirectory: true)
        let logURL = logDir.appendingPathComponent("login-debug.log")
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let line = "\(formatter.string(from: Date())) \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    _ = try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }
}

private struct PageInfo {
    let passwordEncrypt: Bool
    let publicKeyExponent: String?
    let publicKeyModulus: String?

    init(json: [String: Any]) {
        self.passwordEncrypt = String(describing: json["passwordEncrypt"] ?? "false").lowercased() == "true"
        self.publicKeyExponent = json["publicKeyExponent"].map { String(describing: $0) }
        self.publicKeyModulus = json["publicKeyModulus"].map { String(describing: $0) }
    }
}

private extension String {
    func rstrip(_ suffix: Character) -> String {
        var value = self
        while value.last == suffix {
            value.removeLast()
        }
        return value
    }
}
