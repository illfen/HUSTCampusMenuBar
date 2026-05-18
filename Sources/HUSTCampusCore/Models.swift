import Foundation

public enum ProbeStatus: String, Sendable {
    case online
    case captivePortal
    case offline
    case unknown
}

public struct ProbeResult: Sendable {
    public let status: ProbeStatus
    public let portalURL: URL?
    public let queryString: String?
    public let message: String

    public init(
        status: ProbeStatus,
        portalURL: URL? = nil,
        queryString: String? = nil,
        message: String = ""
    ) {
        self.status = status
        self.portalURL = portalURL
        self.queryString = queryString
        self.message = message
    }
}

public struct LoginResult: Sendable {
    public let success: Bool
    public let message: String
    public let userIndex: String?

    public init(success: Bool, message: String, userIndex: String? = nil) {
        self.success = success
        self.message = message
        self.userIndex = userIndex
    }
}

public enum AutologinError: Error, LocalizedError {
    case missingPortalURL
    case missingQueryString
    case missingPassword
    case invalidPortalURL(String)
    case invalidResponse(String)
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingPortalURL:
            return "没有发现校园网认证页"
        case .missingQueryString:
            return "认证页缺少 queryString"
        case .missingPassword:
            return "没有保存密码"
        case .invalidPortalURL(let value):
            return "认证页地址无效：\(value)"
        case .invalidResponse(let value):
            return "认证服务响应异常：\(value)"
        case .requestFailed(let value):
            return "请求失败：\(value)"
        }
    }
}
