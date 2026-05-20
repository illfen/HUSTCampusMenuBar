# HUST Campus Autologin

华中科技大学校园网 ePortal 自动重连工具。支持 macOS（菜单栏 app）和 Linux（CLI / Bash 脚本）。

## 功能

- 自动检测校园网 captive portal 并完成登录，全程无需手动操作
- 支持 `pageInfo` 公钥加密流程 + HUST 旧版 RSA 加密 fallback
- 定时探测（默认 30 秒），断线自动重连
- Swift CLI 密码本地混淆存储（XOR + Base64）；Bash 版使用 0600 权限配置文件保存 Base64 字段，避免特殊字符破坏配置，但不是强加密

## 三种使用方式

| 平台 | 方式 | 适用场景 |
|------|------|----------|
| macOS | 菜单栏 app | 个人电脑，有图形界面 |
| Linux | Swift CLI | 想要原生编译的二进制 |
| Linux | **Bash 脚本** | **服务器最佳，无需编译** |

---

## macOS 菜单栏版

### 系统要求

- macOS 13.0+
- Swift 6.0+（仅源码运行需要）

### 源码运行

```bash
git clone https://github.com/illfen/HUSTCampusMenuBar.git
cd HUSTCampusMenuBar
swift run HUSTCampusMenuBar
```

启动后点击菜单栏梧桐叶图标 → 设置，填写账号和密码。

### 打包成 .app

```bash
chmod +x scripts/build-app.sh
scripts/build-app.sh
open "dist/HUST Campus Autologin.app"
```

未签名 app，首次打开如遇 Gatekeeper 拦截，右键 → 打开即可。

### 功能特性

- 菜单栏梧桐叶图标，状态点实时显示网络状态（绿色在线、橙色认证中、红色离线）
- 登录成功后自动关闭系统的 Captive Network Assistant 弹窗（需要授权辅助功能）
- 使用 Network.framework 绑定物理网卡接口（默认有线，失败 fallback 到默认接口），绕过 TUN/VPN
- 日志写入 `~/Library/Logs/HUSTCampusMenuBar/watch.log`，自动轮转（5MB）

### 配合代理软件使用

如果你使用 Clash/Surge 等代理软件的 TUN 模式，本工具的探测和登录请求会先尝试绑定物理接口直连，绕过 TUN 隧道。

如果仍有问题，可在代理规则中添加：
- 规则类型：`PROCESS-NAME`
- 规则内容：`HUSTCampusMenuBar`
- 代理策略：`DIRECT`

---

## Linux Bash 脚本版（推荐服务器使用）

无需 Swift，只需要 `curl`、`python3`（Ubuntu 通常自带）。

### 安装

```bash
mkdir -p ~/.local/bin
curl -o ~/.local/bin/hust-autologin.sh https://raw.githubusercontent.com/illfen/HUSTCampusMenuBar/main/scripts/hust-autologin.sh
chmod +x ~/.local/bin/hust-autologin.sh
```

### 使用

```bash
~/.local/bin/hust-autologin.sh init     # 初始化（输入学号和密码）
~/.local/bin/hust-autologin.sh status   # 检测网络状态
~/.local/bin/hust-autologin.sh login    # 立即登录一次
~/.local/bin/hust-autologin.sh watch    # 后台守护（默认命令）
```

配置文件：`~/.config/hust-autologin/config`（权限 600；Base64 不是加密）
日志文件：`~/.local/state/hust-autologin/watch.log`

### 配 systemd 用户服务（开机自启）

创建 `~/.config/systemd/user/hust-autologin.service`：

```ini
[Unit]
Description=HUST Campus Auto-Login
After=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/hust-autologin.sh watch
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

启用：

```bash
systemctl --user daemon-reload
systemctl --user enable --now hust-autologin

# 服务器场景：确保退出 SSH 后服务继续运行
loginctl enable-linger $USER

# 查看状态
systemctl --user status hust-autologin

# 查看日志
journalctl --user -u hust-autologin -f
```

---

## Linux Swift CLI 版

如果你的 Linux 上有 Swift 环境，可以用编译版的 CLI（功能与 Bash 脚本一致，但启动更快）。

```bash
git clone https://github.com/illfen/HUSTCampusMenuBar.git
cd HUSTCampusMenuBar
bash scripts/install-linux.sh

hust-autologin init --username <学号>
hust-autologin login
systemctl --user enable --now hust-autologin
loginctl enable-linger $USER
```

> 注意：Swift CLI 版未在主流 Linux 发行版上做完整验证，如遇编译错误请优先使用 Bash 脚本版。

---

## 项目结构

```
Sources/
├── HUSTCampusCore/          # 跨平台核心逻辑
│   ├── AutologinService.swift
│   ├── NetworkProbe.swift        # 网络探测
│   ├── EportalClient.swift       # ePortal 登录客户端
│   ├── DirectHTTPClient.swift    # HTTP 客户端（macOS: Network.framework / Linux: POSIX socket）
│   ├── RSAEncryptor.swift        # RSA 密码加密
│   ├── PortalURL.swift
│   ├── FormEncoding.swift
│   └── Models.swift
├── HUSTCampusMenuBar/       # macOS 菜单栏 UI
└── HUSTCampusCLI/           # Linux/macOS CLI 守护进程
scripts/
├── build-app.sh             # macOS .app 打包
├── install-linux.sh         # Linux Swift CLI 安装
├── hust-autologin.sh        # 纯 Bash 脚本（推荐）
└── hust-autologin.service   # systemd 用户服务模板
```

## 工作原理

1. 使用多个 HTTP 探测地址（绑定物理接口直连）判断网络状态
2. 如果请求被校园网劫持到 `eportal/index.jsp?...`，提取完整认证页地址
3. 从认证页地址解析 `queryString`，推导认证接口基址
4. 调用 `InterFace.do?method=pageInfo` 获取登录参数和 RSA 公钥
5. 生成 `password + ">" + mac` 并用 RSA 公钥加密
6. 调用 `InterFace.do?method=login` 提交认证
7. macOS 版登录成功后自动关闭系统 Captive Network Assistant 弹窗

## 当前限制

- 只处理 ePortal Web 认证，不处理 802.1X 接入认证（学校官方 rjsupplicant 那种）
- macOS 版默认尝试有线接口，无线场景会自动 fallback
- Swift CLI 版尚未在 Linux 上完整验证，推荐使用 Bash 脚本版

## License

MIT License © 2026 jango
