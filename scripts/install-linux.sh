#!/usr/bin/env bash
set -euo pipefail

echo "=== HUST Campus Autologin - Linux 安装脚本 ==="
echo ""

# 检查 Swift
if ! command -v swift &> /dev/null; then
    echo "错误: 未找到 Swift 编译器"
    echo "请先安装 Swift: https://www.swift.org/install/"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="$HOME/.local/bin"
SERVICE_DIR="$HOME/.config/systemd/user"

echo "1. 编译项目..."
cd "$SCRIPT_DIR"
swift build -c release --product hust-autologin

echo "2. 安装二进制..."
mkdir -p "$INSTALL_DIR"
cp ".build/release/hust-autologin" "$INSTALL_DIR/hust-autologin"
chmod +x "$INSTALL_DIR/hust-autologin"
echo "   已安装到: $INSTALL_DIR/hust-autologin"

echo "3. 安装 systemd 用户服务..."
mkdir -p "$SERVICE_DIR"
cp scripts/hust-autologin.service "$SERVICE_DIR/hust-autologin.service"
systemctl --user daemon-reload
echo "   服务文件已安装"

echo ""
echo "=== 安装完成 ==="
echo ""
echo "接下来请执行:"
echo ""
echo "  # 初始化配置（输入学号和密码）"
echo "  hust-autologin init --username <你的学号>"
echo ""
echo "  # 测试登录"
echo "  hust-autologin login"
echo ""
echo "  # 启用开机自启"
echo "  systemctl --user enable --now hust-autologin"
echo ""
echo "  # 服务器场景：确保退出 SSH 后服务继续运行"
echo "  loginctl enable-linger \$USER"
echo ""
echo "  # 查看服务状态"
echo "  systemctl --user status hust-autologin"
echo ""
echo "  # 查看日志"
echo "  journalctl --user -u hust-autologin -f"
echo ""
