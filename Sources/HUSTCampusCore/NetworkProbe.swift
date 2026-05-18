import Foundation

public final class NetworkProbe: Sendable {
    private let client: DirectHTTPClient
    private let probeURLs: [URL]
    private let manualPortalURL: @Sendable () -> URL?

    private let eportalPattern = try! NSRegularExpression(
        pattern: #"https?://[^'"<>\s]+/eportal/index\.jsp\?[^'"<>\s]+"#,
        options: [.caseInsensitive]
    )

    public init(
        client: DirectHTTPClient,
        probeURLs: [URL] = [
            URL(string: "http://connectivitycheck.gstatic.com/generate_204")!,
            URL(string: "http://www.baidu.com/")!,
            URL(string: "http://captive.apple.com/hotspot-detect.html")!,
            URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        ],
        manualPortalURL: @escaping @Sendable () -> URL? = { nil }
    ) {
        self.client = client
        self.probeURLs = probeURLs
        self.manualPortalURL = manualPortalURL
    }

    public func probe() async -> ProbeResult {
        var lastError = ""
        for url in probeURLs {
            do {
                // 使用 Network.framework 直连 WiFi 物理接口，绕过 TUN/VPN
                let (data, http) = try await client.getRaw(url)

                // 诊断日志
                let bodyPreview = String(data: data.prefix(200), encoding: .utf8) ?? "(non-utf8)"
                probeLog("probe \(url.absoluteString) -> \(http.statusCode), body=\(bodyPreview.prefix(150))")

                // 302/301 重定向：校园网网关通常通过重定向劫持
                if [301, 302, 303, 307, 308].contains(http.statusCode) {
                    if let location = http.value(forHTTPHeaderField: "Location") ?? http.value(forHTTPHeaderField: "location"),
                       let locationURL = URL(string: location) {
                        probeLog("redirect to: \(location)")
                        if isPortalIndex(locationURL) {
                            return captive(locationURL, message: "发现校园网认证页（重定向）")
                        }
                        // 重定向到非原始目标 = 被劫持，尝试跟随一次拿到认证页
                        if let portalURL = await followRedirectForPortalRaw(locationURL) {
                            return captive(portalURL, message: "发现校园网认证页（二次跳转）")
                        }
                    }
                    // 有重定向但找不到 portal URL，尝试从 body 提取
                    if let portalURL = extractPortalURLFromData(data) {
                        return captive(portalURL, message: "发现校园网认证页")
                    }
                    continue
                }

                if let portalURL = extractPortalURLFromData(data) {
                    return captive(portalURL, message: "发现校园网认证页")
                }
                if (200 ..< 300).contains(http.statusCode) || http.statusCode == 304 {
                    return ProbeResult(status: .online, message: "网络在线")
                }
            } catch {
                lastError = error.localizedDescription
                probeLog("probe \(url.absoluteString) error: \(lastError)")
            }
        }

        if let manual = manualPortalURL() {
            return captive(manual, message: "使用手动认证页")
        }
        return ProbeResult(status: .offline, message: lastError.isEmpty ? "探测失败" : lastError)
    }

    /// 跟随一次重定向（raw TCP），看目标页面是否包含 eportal 链接
    private func followRedirectForPortalRaw(_ url: URL) async -> URL? {
        guard let (data, _) = try? await client.getRaw(url) else {
            return nil
        }
        return extractPortalURLFromData(data)
    }

    private func extractPortalURLFromData(_ data: Data) -> URL? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard
            let match = eportalPattern.firstMatch(in: text, range: range),
            let matchRange = Range(match.range, in: text)
        else {
            return nil
        }
        let raw = String(text[matchRange])
            .replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: raw)
    }

    private func probeLog(_ message: String) {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/HUSTCampusMenuBar", isDirectory: true)
        let logURL = logDir.appendingPathComponent("probe-debug.log")
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

    public func extractPortalURL(data: Data, response: URLResponse) -> URL? {
        if let url = response.url, isPortalIndex(url) {
            return url
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard
            let match = eportalPattern.firstMatch(in: text, range: range),
            let matchRange = Range(match.range, in: text)
        else {
            return nil
        }
        let raw = String(text[matchRange])
            .replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: raw)
    }

    private func captive(_ portalURL: URL, message: String) -> ProbeResult {
        do {
            let parsed = try PortalURL.parse(portalURL)
            return ProbeResult(
                status: .captivePortal,
                portalURL: parsed.portalURL,
                queryString: parsed.queryString,
                message: message
            )
        } catch {
            return ProbeResult(status: .unknown, portalURL: portalURL, message: error.localizedDescription)
        }
    }

    private func isPortalIndex(_ url: URL) -> Bool {
        url.path.hasSuffix("/eportal/index.jsp") && (url.query?.isEmpty == false)
    }

    private func looksOnline(response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else {
            return false
        }
        // 302 不算 online：很多 captive portal 通过 302 重定向到认证页
        if http.statusCode == 302 {
            return false
        }
        return (200 ..< 300).contains(http.statusCode) || http.statusCode == 304
    }
}
