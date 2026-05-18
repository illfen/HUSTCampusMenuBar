import ArgumentParser
import Foundation
import HUSTCampusCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

@main
struct HUSTAutologin: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hust-autologin",
        abstract: "华中科技大学校园网 ePortal 自动重连工具",
        subcommands: [Init.self, Login.self, Watch.self, Status.self],
        defaultSubcommand: Watch.self
    )
}

// MARK: - Init command

struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "初始化配置（设置账号密码）")

    @Option(name: .long, help: "校园网账号（学号）")
    var username: String

    @Option(name: .long, help: "探测间隔（秒）")
    var interval: Int = 30

    @Option(name: .long, help: "手动指定认证页 URL（可选）")
    var manualURL: String?

    func run() async throws {
        let config = CLIConfig.shared
        config.username = username
        config.intervalSeconds = interval
        config.manualPortalURL = manualURL ?? ""
        config.save()

        print("账号已保存: \(username)")
        print("探测间隔: \(interval) 秒")
        if let url = manualURL, !url.isEmpty {
            print("手动认证页: \(url)")
        }

        // 交互式输入密码
        print("请输入密码: ", terminator: "")
        fflush(stdout)
        if let password = readPassword() {
            config.savePassword(password)
            print("密码已保存")
        } else {
            print("错误: 无法读取密码")
        }
    }
}

// MARK: - Login command

struct Login: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "立即尝试登录")

    func run() async throws {
        let config = CLIConfig.shared
        guard !config.username.isEmpty else {
            print("错误: 请先运行 hust-autologin init --username <学号>")
            throw ExitCode.failure
        }
        guard let password = config.loadPassword(), !password.isEmpty else {
            print("错误: 没有保存密码，请运行 hust-autologin init")
            throw ExitCode.failure
        }

        let service = makeService(config: config)
        print("正在检测网络...")
        let result = await service.loginIfNeeded()
        if result.success {
            print("✓ \(result.message)")
        } else {
            print("✗ \(result.message)")
            throw ExitCode.failure
        }
    }
}

// MARK: - Watch command (daemon)

struct Watch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "常驻后台，自动探测并重连（默认命令）")

    @Option(name: .long, help: "探测间隔（秒），覆盖配置文件")
    var interval: Int?

    func run() async throws {
        let config = CLIConfig.shared
        guard !config.username.isEmpty else {
            print("错误: 请先运行 hust-autologin init --username <学号>")
            throw ExitCode.failure
        }
        guard let password = config.loadPassword(), !password.isEmpty else {
            print("错误: 没有保存密码，请运行 hust-autologin init")
            throw ExitCode.failure
        }

        let intervalSec = interval ?? config.intervalSeconds
        let service = makeService(config: config)

        print("HUST Campus Autologin 守护进程启动")
        print("账号: \(config.username)")
        print("探测间隔: \(intervalSec) 秒")
        print("按 Ctrl+C 退出")
        print("---")

        // 写 PID 文件
        writePIDFile()
        defer { removePIDFile() }

        // 信号处理
        signal(SIGINT) { _ in
            print("\n正在退出...")
            removePIDFile()
            Foundation.exit(0)
        }
        signal(SIGTERM) { _ in
            removePIDFile()
            Foundation.exit(0)
        }

        // 主循环
        while true {
            let result = await service.loginIfNeeded()
            let timestamp = ISO8601DateFormatter().string(from: Date())
            if result.success {
                if result.message != "网络在线" {
                    print("[\(timestamp)] ✓ 登录成功: \(result.message)")
                }
            } else {
                print("[\(timestamp)] ✗ \(result.message)")
            }

            try await Task.sleep(nanoseconds: UInt64(intervalSec) * 1_000_000_000)
        }
    }
}

// MARK: - Status command

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "检测当前网络状态")

    func run() async throws {
        let config = CLIConfig.shared
        let client = DirectHTTPClient()
        let probe = NetworkProbe(client: client, manualPortalURL: {
            URL(string: config.manualPortalURL)
        })

        print("正在探测网络...")
        let result = await probe.probe()
        switch result.status {
        case .online:
            print("✓ 网络在线")
        case .captivePortal:
            print("⚠ 需要认证")
            if let url = result.portalURL {
                print("  认证页: \(url.absoluteString)")
            }
        case .offline:
            print("✗ 网络离线: \(result.message)")
        case .unknown:
            print("? 状态未知: \(result.message)")
        }
    }
}

// MARK: - Helpers

func makeService(config: CLIConfig) -> AutologinService {
    let client = DirectHTTPClient()
    let probe = NetworkProbe(client: client, manualPortalURL: {
        URL(string: config.manualPortalURL)
    })
    let eportal = EportalClient(client: client)
    return AutologinService(
        probe: probe,
        eportal: eportal,
        credentials: {
            let username = config.username
            guard let password = config.loadPassword(), !password.isEmpty else {
                throw AutologinError.missingPassword
            }
            return (username, password)
        }
    )
}

func readPassword() -> String? {
    #if os(Linux)
    // Linux: 关闭终端回显读取密码
    var oldTermios = termios()
    tcgetattr(STDIN_FILENO, &oldTermios)
    var newTermios = oldTermios
    newTermios.c_lflag &= ~UInt32(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)
    defer {
        tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
        print("")
    }
    return readLine(strippingNewline: true)
    #else
    // macOS: 使用 getpass 或直接 readLine
    if let pass = getpass("") {
        return String(cString: pass)
    }
    return readLine(strippingNewline: true)
    #endif
}

// MARK: - PID file

func pidFilePath() -> String {
    #if os(macOS)
    let dir = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/HUSTCampusMenuBar"
    #else
    let xdgRuntime = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"]
        ?? "/tmp"
    let dir = xdgRuntime
    #endif
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir + "/hust-autologin.pid"
}

func writePIDFile() {
    let pid = ProcessInfo.processInfo.processIdentifier
    try? "\(pid)".write(toFile: pidFilePath(), atomically: true, encoding: .utf8)
}

func removePIDFile() {
    try? FileManager.default.removeItem(atPath: pidFilePath())
}

// MARK: - CLI Config

final class CLIConfig: @unchecked Sendable {
    static let shared = CLIConfig()

    private let configURL: URL
    private let secretsURL: URL

    var username: String = ""
    var intervalSeconds: Int = 30
    var manualPortalURL: String = ""

    private init() {
        #if os(macOS)
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/HUSTCampusMenuBar", isDirectory: true)
        #else
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? (FileManager.default.homeDirectoryForCurrentUser.path + "/.config")
        let configDir = URL(fileURLWithPath: xdgConfig).appendingPathComponent("hust-autologin", isDirectory: true)
        #endif
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        configURL = configDir.appendingPathComponent("config.json")
        secretsURL = configDir.appendingPathComponent(".secrets")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        username = json["username"] as? String ?? ""
        intervalSeconds = json["intervalSeconds"] as? Int ?? 30
        manualPortalURL = json["manualPortalURL"] as? String ?? ""
    }

    func save() {
        let json: [String: Any] = [
            "username": username,
            "intervalSeconds": intervalSeconds,
            "manualPortalURL": manualPortalURL
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    func savePassword(_ password: String) {
        let obfuscated = obfuscate(password)
        try? obfuscated.write(to: secretsURL, atomically: true, encoding: .utf8)
        #if os(Linux)
        chmod(secretsURL.path, 0o600)
        #endif
    }

    func loadPassword() -> String? {
        guard let encoded = try? String(contentsOf: secretsURL, encoding: .utf8) else {
            return nil
        }
        return deobfuscate(encoded)
    }

    private var key: Data {
        let machineID = (ProcessInfo.processInfo.hostName).data(using: .utf8) ?? Data("HUSTCampus".utf8)
        var keyData = Data(count: 32)
        for i in 0..<32 {
            keyData[i] = machineID[i % machineID.count] ^ 0xA5
        }
        return keyData
    }

    private func obfuscate(_ plaintext: String) -> String {
        let input = Data(plaintext.utf8)
        let k = key
        var output = Data(count: input.count)
        for i in 0..<input.count {
            output[i] = input[i] ^ k[i % k.count]
        }
        return output.base64EncodedString()
    }

    private func deobfuscate(_ encoded: String) -> String? {
        guard let data = Data(base64Encoded: encoded) else { return nil }
        let k = key
        var output = Data(count: data.count)
        for i in 0..<data.count {
            output[i] = data[i] ^ k[i % k.count]
        }
        return String(data: output, encoding: .utf8)
    }
}
