import Foundation

public actor AutologinService {
    private let probe: NetworkProbe
    private let eportal: EportalClient
    private let credentials: @Sendable () async throws -> (username: String, password: String)

    public init(
        probe: NetworkProbe,
        eportal: EportalClient,
        credentials: @escaping @Sendable () async throws -> (username: String, password: String)
    ) {
        self.probe = probe
        self.eportal = eportal
        self.credentials = credentials
    }

    public func check() async -> ProbeResult {
        await probe.probe()
    }

    public func loginIfNeeded() async -> LoginResult {
        let probeResult = await probe.probe()
        switch probeResult.status {
        case .online:
            return LoginResult(success: true, message: "网络在线")
        case .captivePortal:
            guard let portalURL = probeResult.portalURL else {
                return LoginResult(success: false, message: AutologinError.missingPortalURL.localizedDescription)
            }
            do {
                let credential = try await credentials()
                return try await eportal.login(
                    username: credential.username,
                    password: credential.password,
                    portalURL: portalURL
                )
            } catch {
                return LoginResult(success: false, message: error.localizedDescription)
            }
        case .offline, .unknown:
            return LoginResult(success: false, message: probeResult.message)
        }
    }
}
