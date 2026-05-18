import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let usernameField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let manualURLField = NSTextField()
    private let intervalPopup = NSPopUpButton()
    private let autoReconnectButton = NSButton(checkboxWithTitle: "自动重连", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 270),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "HUST 校园网"
        window.center()
        self.init(window: window)
        buildUI()
        loadSettings()
    }

    private func buildUI() {
        guard let content = window?.contentView else {
            return
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22)
        ])

        stack.addArrangedSubview(row(label: "账号", control: usernameField))
        passwordField.placeholderString = "留空表示不修改已保存密码"
        stack.addArrangedSubview(row(label: "密码", control: passwordField))
        manualURLField.placeholderString = "可选：完整 ePortal 登录页 URL"
        stack.addArrangedSubview(row(label: "认证页", control: manualURLField))

        intervalPopup.addItems(withTitles: ["15 秒", "30 秒", "60 秒", "120 秒"])
        stack.addArrangedSubview(row(label: "探测间隔", control: intervalPopup))

        autoReconnectButton.target = self
        autoReconnectButton.action = #selector(toggleAutoReconnect)
        stack.addArrangedSubview(autoReconnectButton)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(statusLabel)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .centerY
        buttons.distribution = .fillEqually

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        buttons.addArrangedSubview(cancelButton)
        buttons.addArrangedSubview(saveButton)
        stack.addArrangedSubview(buttons)
    }

    private func row(label: String, control: NSControl) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 72).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        return row
    }

    private func loadSettings() {
        let settings = AppSettings.shared
        usernameField.stringValue = settings.username
        manualURLField.stringValue = settings.manualPortalURL
        autoReconnectButton.state = settings.autoReconnect ? .on : .off

        let title = "\(settings.intervalSeconds) 秒"
        if intervalPopup.itemTitles.contains(title) {
            intervalPopup.selectItem(withTitle: title)
        } else {
            intervalPopup.selectItem(withTitle: "30 秒")
        }
    }

    @objc private func toggleAutoReconnect() {}

    @objc private func cancel() {
        close()
    }

    @objc private func save() {
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            statusLabel.stringValue = "账号不能为空"
            return
        }

        AppSettings.shared.username = username
        AppSettings.shared.manualPortalURL = manualURLField.stringValue
        AppSettings.shared.autoReconnect = autoReconnectButton.state == .on
        AppSettings.shared.intervalSeconds = Int(intervalPopup.selectedItem?.title.components(separatedBy: " ").first ?? "30") ?? 30

        if !passwordField.stringValue.isEmpty {
            do {
                try KeychainStore.shared.savePassword(passwordField.stringValue, username: username)
            } catch {
                statusLabel.stringValue = error.localizedDescription
                return
            }
        }

        statusLabel.stringValue = "已保存"
        AppLogger.shared.info("settings saved")
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        close()
    }
}
