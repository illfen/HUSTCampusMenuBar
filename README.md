# HUST Campus Autologin for macOS

华中科技大学校园网 ePortal 自动重连工具，原生 macOS 菜单栏应用。

## 功能

- 菜单栏梧桐叶图标，状态点实时显示网络状态（绿色在线、橙色认证中、红色离线）
- 自动检测校园网 captive portal 并完成登录，全程无需手动操作
- 登录成功后自动关闭系统弹出的认证窗口
- 支持 `pageInfo` 公钥加密流程 + HUST 旧版 RSA 加密 fallback
- 使用 Network.framework 绑定 WiFi 物理接口，绕过 TUN/VPN 代理
- 定时探测（默认 30 秒），断线自动重连
- 密码本地加密存储，不使用 Keychain（避免未签名 app 反复弹授权）
- 日志写入 `~/Library/Logs/HUSTCampusMenuBar/watch.log`，自动轮转（5MB）

## 系统要求

- macOS 13.0+
- Swift 6.0+
- 连接华科校园网（HUST_WIRELESS 等）

## 安装与运行

### 源码运行（推荐开发者）

```bash
git clone https://github.com/jango/HUSTCampusMenuBar.git
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

## 使用说明

1. 打开 app，菜单栏出现梧桐叶图标
2. 点击图标 → 设置，填写校园网账号和密码，保存
3. 确保 Wi-Fi 设置中 HUST_WIRELESS 已勾选"自动加入此网络"
4. 完成。之后断线会自动重连，无需手动操作

## 配合代理软件使用

如果你使用 Clash/Surge 等代理软件的 TUN 模式，本工具的探测和登录请求通过 `Network.framework` 绑定 WiFi 物理接口直连，不经过 TUN 隧道。

如果仍有问题，可在代理规则中添加：
- 规则类型：`PROCESS-NAME`
- 规则内容：`HUSTCampusMenuBar`
- 代理策略：`DIRECT`

## 项目结构

```
Sources/
├── HUSTCampusCore/          # 核心逻辑（可复用）
│   ├── AutologinService.swift    # 自动登录服务
│   ├── NetworkProbe.swift        # 网络探测（绕过 TUN）
│   ├── EportalClient.swift       # ePortal 登录客户端
│   ├── DirectHTTPClient.swift    # HTTP 客户端（Network.framework）
│   ├── RSAEncryptor.swift        # RSA 密码加密
│   ├── PortalURL.swift           # 认证页 URL 解析
│   ├── FormEncoding.swift        # 表单编码
│   └── Models.swift              # 数据模型
└── HUSTCampusMenuBar/       # macOS 菜单栏 UI
    ├── main.swift
    ├── AppDelegate.swift
    ├── AppSettings.swift
    ├── KeychainStore.swift       # 本地加密密码存储
    ├── SettingsWindowController.swift
    ├── StatusIconFactory.swift   # 梧桐叶图标绘制
    └── AppLogger.swift
```

## 工作原理

1. 使用多个 HTTP 探测地址（通过 WiFi 物理接口直连）判断网络状态
2. 如果请求被校园网劫持到 `eportal/index.jsp?...`，提取完整认证页地址
3. 从认证页地址解析 `queryString`，推导认证接口基址
4. 调用 `InterFace.do?method=pageInfo` 获取登录参数和 RSA 公钥
5. 生成 `password + ">" + mac` 并用 RSA 公钥加密
6. 调用 `InterFace.do?method=login` 提交认证
7. 登录成功后自动关闭系统 Captive Network Assistant 弹窗

## 当前限制

- 仅支持 macOS，不支持 Linux/Windows（核心逻辑在 HUSTCampusCore 中，可移植）
- 只处理 ePortal Web 认证，不处理 802.1X 接入认证
- 开机自启需手动将 app 添加到 macOS 登录项

## License

MIT License © 2026 jango
