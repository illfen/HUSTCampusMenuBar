import Foundation

public struct ParsedPortalURL: Sendable {
    public let portalURL: URL
    public let baseURL: URL
    public let queryString: String
    public let mac: String
}

public enum PortalURL {
    public static func parse(_ url: URL) throws -> ParsedPortalURL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AutologinError.invalidPortalURL(url.absoluteString)
        }
        guard components.path.hasSuffix("/eportal/index.jsp") else {
            throw AutologinError.invalidPortalURL(url.absoluteString)
        }
        guard let query = components.percentEncodedQuery, !query.isEmpty else {
            throw AutologinError.missingQueryString
        }

        components.path = components.path.replacingOccurrences(
            of: "/index.jsp",
            with: ""
        )
        components.percentEncodedQuery = nil
        components.fragment = nil
        guard let baseURL = components.url else {
            throw AutologinError.invalidPortalURL(url.absoluteString)
        }
        return ParsedPortalURL(
            portalURL: url,
            baseURL: baseURL,
            queryString: query,
            mac: mac(from: query) ?? "111111111"
        )
    }

    public static func mac(from queryString: String) -> String? {
        for pair in queryString.split(separator: "&", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.first == "mac", parts.count == 2 else {
                continue
            }
            return String(parts[1]).removingPercentEncoding ?? String(parts[1])
        }
        return nil
    }
}
