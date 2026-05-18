import Foundation
import Security

enum KeychainStoreError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "密码存储返回错误：\(status)"
        case .invalidData:
            return "密码格式无效"
        }
    }
}

/// 使用本地加密文件存储密码，避免未签名 app 每次读取 Keychain 都弹授权窗口
final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()

    private let fileURL: URL
    private let key: Data

    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/HUSTCampusMenuBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent(".credentials")

        // 使用机器唯一标识作为加密 key（简单 XOR 混淆，不是强加密，但避免明文存储）
        let machineID = (Host.current().name ?? "HUSTCampusMenuBar").data(using: .utf8) ?? Data("HUSTCampusMenuBar".utf8)
        // 扩展到 32 字节
        var keyData = Data(count: 32)
        for i in 0..<32 {
            keyData[i] = machineID[i % machineID.count] ^ 0xA5
        }
        self.key = keyData
    }

    func savePassword(_ password: String, username: String) throws {
        let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else { return }

        var store = loadStore()
        store[account] = obfuscate(password)
        let data = try JSONSerialization.data(withJSONObject: store)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])

        // 设置文件权限为 600（仅当前用户可读写）
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func password(username: String) throws -> String? {
        let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else { return nil }

        let store = loadStore()
        guard let obfuscated = store[account] else { return nil }
        return deobfuscate(obfuscated)
    }

    private func loadStore() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: String] else {
            return [:]
        }
        return dict
    }

    private func obfuscate(_ plaintext: String) -> String {
        let input = Data(plaintext.utf8)
        var output = Data(count: input.count)
        for i in 0..<input.count {
            output[i] = input[i] ^ key[i % key.count]
        }
        return output.base64EncodedString()
    }

    private func deobfuscate(_ encoded: String) -> String? {
        guard let data = Data(base64Encoded: encoded) else { return nil }
        var output = Data(count: data.count)
        for i in 0..<data.count {
            output[i] = data[i] ^ key[i % key.count]
        }
        return String(data: output, encoding: .utf8)
    }
}
