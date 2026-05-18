import Foundation

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    let logURL: URL
    private let queue = DispatchQueue(label: "com.jzy.HUSTCampusMenuBar.log")
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter
    }()

    private init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/HUSTCampusMenuBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appendingPathComponent("watch.log")
    }

    func info(_ message: String) {
        write("INFO", message)
    }

    func warning(_ message: String) {
        write("WARN", message)
    }

    private func write(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        let logURL = self.logURL
        queue.async {
            guard let data = line.data(using: .utf8) else {
                return
            }
            // 日志文件超过 5MB 时自动轮转
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
               let size = attrs[.size] as? UInt64,
               size > 5 * 1024 * 1024 {
                let backupURL = logURL.deletingLastPathComponent().appendingPathComponent("watch.log.old")
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.moveItem(at: logURL, to: backupURL)
            }
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer {
                        try? handle.close()
                    }
                    _ = try? handle.seekToEnd()
                    _ = try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }
}
