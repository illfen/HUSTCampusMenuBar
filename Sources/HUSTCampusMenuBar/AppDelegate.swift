import AppKit
import HUSTCampusCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private let statusItemText = NSMenuItem(title: "状态：启动中", action: nil, keyEquivalent: "")
    private let messageItem = NSMenuItem(title: "消息：-", action: nil, keyEquivalent: "")
    private let autoReconnectItem = NSMenuItem(title: "自动重连", action: #selector(toggleAutoReconnect), keyEquivalent: "")
    private let checkItem = NSMenuItem(title: "立即检测", action: #selector(checkNow), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "立即登录", action: #selector(loginNow), keyEquivalent: "")

    private var settingsWindow: SettingsWindowController?
    private var timer: Timer?
    private var runningTask: Task<Void, Never>?
    private var lastPortalURL: URL?
    private lazy var service = makeService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusMenu()
        updateAutoReconnectMenu()
        updateStatus("启动中", message: "等待首次探测")
        scheduleTimer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .settingsDidChange,
            object: nil
        )
        Task { await performCheck(loginIfCaptive: true) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        runningTask?.cancel()
    }

    private func buildStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleProportionallyDown

        statusItemText.isEnabled = false
        messageItem.isEnabled = false
        autoReconnectItem.target = self
        checkItem.target = self
        loginItem.target = self

        statusMenu.addItem(statusItemText)
        statusMenu.addItem(messageItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(checkItem)
        statusMenu.addItem(loginItem)
        statusMenu.addItem(autoReconnectItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",").targeting(self))
        statusMenu.addItem(NSMenuItem(title: "查看日志", action: #selector(openLogs), keyEquivalent: "l").targeting(self))
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q").targeting(self))

        statusItem.menu = statusMenu
    }

    private func makeService() -> AutologinService {
        let client = DirectHTTPClient()
        let probe = NetworkProbe(
            client: client,
            manualPortalURL: {
                return URL(string: UserDefaults.standard.string(forKey: "manualPortalURL") ?? "")
            }
        )
        let eportal = EportalClient(client: client)
        return AutologinService(
            probe: probe,
            eportal: eportal,
            credentials: {
                let username = await MainActor.run { AppSettings.shared.username }
                guard let password = try KeychainStore.shared.password(username: username), !password.isEmpty else {
                    throw AutologinError.missingPassword
                }
                return (username, password)
            }
        )
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(AppSettings.shared.intervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard AppSettings.shared.autoReconnect else {
                    return
                }
                await self?.performCheck(loginIfCaptive: true)
            }
        }
    }

    @objc private func checkNow() {
        Task { await performCheck(loginIfCaptive: false) }
    }

    @objc private func loginNow() {
        Task { await performLogin() }
    }

    @objc private func toggleAutoReconnect() {
        AppSettings.shared.autoReconnect.toggle()
        updateAutoReconnectMenu()
        scheduleTimer()
    }

    @objc private func settingsDidChange() {
        updateAutoReconnectMenu()
        scheduleTimer()
    }

    @objc private func openSettings() {
        let controller = settingsWindow ?? SettingsWindowController()
        settingsWindow = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openLogs() {
        NSWorkspace.shared.open(AppLogger.shared.logURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func performCheck(loginIfCaptive: Bool) async {
        guard runningTask == nil else {
            return
        }
        runningTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.setBusy(true)
                self.updateStatus("检测中", message: "正在探测网络")
            }
            let result = await self.service.check()
            await MainActor.run {
                self.lastPortalURL = result.portalURL
                switch result.status {
                case .online:
                    self.updateStatus("在线", message: result.message)
                    AppLogger.shared.info("network online")
                case .captivePortal:
                    self.updateStatus("需认证", message: result.message)
                    AppLogger.shared.warning("captive portal: \(result.portalURL?.absoluteString ?? "-")")
                case .offline:
                    self.updateStatus("离线", message: result.message)
                    AppLogger.shared.warning("network offline: \(result.message)")
                case .unknown:
                    self.updateStatus("未知", message: result.message)
                    AppLogger.shared.warning("network unknown: \(result.message)")
                }
            }
            if loginIfCaptive && result.status == .captivePortal {
                await self.performLogin()
            }
            await MainActor.run {
                self.setBusy(false)
                self.runningTask = nil
            }
        }
        await runningTask?.value
    }

    private func performLogin() async {
        await MainActor.run {
            setBusy(true)
            updateStatus("登录中", message: "正在提交校园网认证")
        }
        let result = await service.loginIfNeeded()
        await MainActor.run {
            if result.success {
                updateStatus("在线", message: result.message)
                AppLogger.shared.info("login success: \(result.message)")
                dismissCaptivePortalWindow()
            } else {
                updateStatus("失败", message: result.message)
                AppLogger.shared.warning("login failed: \(result.message)")
            }
            setBusy(false)
        }
    }

    /// 登录成功后自动关闭系统的 Captive Network Assistant 弹窗
    private func dismissCaptivePortalWindow() {
        DispatchQueue.global(qos: .utility).async {
            let script = """
            tell application "System Events"
                if exists process "Captive Network Assistant" then
                    tell process "Captive Network Assistant"
                        click button 1 of window 1
                    end tell
                end if
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    let msg = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
                    if msg.contains("assistive") || msg.contains("accessibility") {
                        DispatchQueue.main.async {
                            AppLogger.shared.warning("无法关闭认证弹窗：需要辅助功能权限。请前往 系统设置 → 隐私与安全性 → 辅助功能，添加本 app。")
                        }
                    }
                }
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        checkItem.isEnabled = !busy
        loginItem.isEnabled = !busy
    }

    private func updateStatus(_ status: String, message: String) {
        statusItem.button?.image = StatusIconFactory.icon(for: status)
        statusItem.button?.toolTip = "HUST 校园网：\(status)"
        statusItemText.title = "状态：\(status)"
        messageItem.title = "消息：\(message.isEmpty ? "-" : message)"
    }

    private func updateAutoReconnectMenu() {
        autoReconnectItem.state = AppSettings.shared.autoReconnect ? .on : .off
    }
}

private extension NSMenuItem {
    func targeting(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}

extension Notification.Name {
    static let settingsDidChange = Notification.Name("HUSTCampusSettingsDidChange")
}
