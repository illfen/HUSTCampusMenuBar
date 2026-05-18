#!/usr/bin/env bash
# 华中科技大学校园网 ePortal 自动登录脚本
# 依赖: curl, openssl, python3 (用于 RSA 大数运算)
# 用法: hust-autologin.sh [watch|login|status]

set -uo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hust-autologin"
CONFIG_FILE="$CONFIG_DIR/config"
LOG_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hust-autologin/watch.log"
INTERVAL=30
TIMEOUT=8

mkdir -p "$CONFIG_DIR" "$(dirname "$LOG_FILE")"

# HUST 旧版 RSA 公钥（modulus 和 exponent）
LEGACY_MODULUS="94dd2a8675fb779e6b9f7103698634cd400f27a154afa67af6166a43fc26417222a79506d34cacc7641946abda1785b7acf9910ad6a0978c91ec84d40b71d2891379af19ffb333e7517e390bd26ac312fe940c340466b4a5d4af1d65c3b5944078f96a1a51a5a53e4bc302818b7c9f63c4a1b07bd7d874cef1c3d4b2f5eb7871"
LEGACY_EXPONENT="10001"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# RSA 加密：password>mac，用 Python 做大数运算
rsa_encrypt() {
    local password="$1"
    local mac="$2"
    local modulus_hex="$3"
    local exponent_hex="$4"

    python3 <<EOF
password = "$password"
mac = "$mac"
modulus = int("$modulus_hex", 16)
exponent = int("$exponent_hex", 16)

payload = f"{password}>{mac}"
# HUST eportal 要求：字符串反转，每个字符 utf-8 编码后小端序拼成大整数
reversed_str = payload[::-1]
data = reversed_str.encode("utf-8")
m = int.from_bytes(data, byteorder="little")
c = pow(m, exponent, modulus)
# 输出 256 位 hex（左侧补 0）
print(f"{c:0512x}")
EOF
}

# 探测网络状态，输出认证页 URL（如果需要认证）
probe_network() {
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}|%{redirect_url}" \
        --max-time "$TIMEOUT" --connect-timeout 3 \
        --noproxy '*' \
        "http://www.baidu.com/" 2>/dev/null) || return 1

    local code="${response%%|*}"
    local redirect="${response##*|}"

    if [[ "$code" == "200" ]]; then
        # 没有重定向，可能在线，再检查 baidu 实际内容
        local body
        body=$(curl -s --max-time "$TIMEOUT" --noproxy '*' \
            "http://www.baidu.com/" 2>/dev/null) || return 1
        # 如果 body 里有 eportal/index.jsp，是被劫持了
        local portal_url
        portal_url=$(echo "$body" | grep -oE 'http://[^"'"'"' <>]*eportal/index\.jsp\?[^"'"'"' <>]*' | head -1)
        if [[ -n "$portal_url" ]]; then
            echo "$portal_url"
            return 2  # captive portal
        fi
        return 0  # online
    elif [[ "$code" =~ ^30[0-9]$ ]] && [[ "$redirect" == *"eportal/index.jsp"* ]]; then
        echo "$redirect"
        return 2  # captive portal
    fi
    return 1  # offline or unknown
}

# 从 portal URL 解析 baseURL、queryString、mac
parse_portal_url() {
    local portal_url="$1"
    # baseURL = portal_url 去掉 /index.jsp?... 后的部分
    PORTAL_BASE=$(echo "$portal_url" | sed -E 's|/index\.jsp\?.*$||')
    PORTAL_QUERY=$(echo "$portal_url" | sed -E 's|^[^?]+\?||')
    # 从 query 中提取 mac
    PORTAL_MAC=$(echo "$PORTAL_QUERY" | grep -oE 'mac=[^&]*' | cut -d= -f2)
    PORTAL_MAC="${PORTAL_MAC:-111111111}"
}

# 提交登录
do_login() {
    local username="$1"
    local password="$2"
    local portal_url="$3"

    parse_portal_url "$portal_url"
    log "解析认证页: base=$PORTAL_BASE mac=$PORTAL_MAC"

    # 先尝试 pageInfo 拿到当前公钥
    local page_info
    page_info=$(curl -s --max-time "$TIMEOUT" --noproxy '*' \
        -X POST "$PORTAL_BASE/InterFace.do?method=pageInfo" \
        -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
        --data-urlencode "queryString=$PORTAL_QUERY" 2>/dev/null) || true

    local modulus exponent password_encrypted password_encrypt
    if [[ -n "$page_info" ]] && echo "$page_info" | grep -q "passwordEncrypt.*true"; then
        modulus=$(echo "$page_info" | grep -oE '"publicKeyModulus":"[^"]*"' | cut -d'"' -f4)
        exponent=$(echo "$page_info" | grep -oE '"publicKeyExponent":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$modulus" && -n "$exponent" ]]; then
            log "使用 pageInfo 公钥加密"
            password_encrypted=$(rsa_encrypt "$password" "$PORTAL_MAC" "$modulus" "$exponent")
            password_encrypt="true"
        fi
    fi

    # Fallback 到 legacy 公钥
    if [[ -z "${password_encrypted:-}" ]]; then
        log "使用 legacy 公钥加密"
        password_encrypted=$(rsa_encrypt "$password" "$PORTAL_MAC" "$LEGACY_MODULUS" "$LEGACY_EXPONENT")
        password_encrypt="true"
    fi

    # 提交登录
    local response
    response=$(curl -s --max-time "$TIMEOUT" --noproxy '*' \
        -X POST "$PORTAL_BASE/InterFace.do?method=login" \
        -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
        -H "Referer: $PORTAL_BASE/index.jsp?$PORTAL_QUERY" \
        --data-urlencode "userId=$username" \
        --data-urlencode "password=$password_encrypted" \
        --data-urlencode "service=" \
        --data-urlencode "queryString=$PORTAL_QUERY" \
        --data-urlencode "operatorPwd=" \
        --data-urlencode "operatorUserId=" \
        --data-urlencode "validcode=" \
        --data-urlencode "passwordEncrypt=$password_encrypt" 2>/dev/null) || true

    if echo "$response" | grep -q '"result":"success"'; then
        log "✓ 登录成功"
        return 0
    else
        local msg
        msg=$(echo "$response" | grep -oE '"message":"[^"]*"' | cut -d'"' -f4)
        log "✗ 登录失败: ${msg:-未知错误}"
        return 1
    fi
}

# 加载配置
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    [[ -n "${USERNAME:-}" && -n "${PASSWORD:-}" ]]
}

# 初始化配置
cmd_init() {
    read -rp "学号: " username
    read -rsp "密码: " password
    echo
    cat > "$CONFIG_FILE" <<EOF
USERNAME="$username"
PASSWORD="$password"
EOF
    chmod 600 "$CONFIG_FILE"
    echo "配置已保存到 $CONFIG_FILE"
}

# 单次登录
cmd_login() {
    if ! load_config; then
        echo "请先运行: $0 init"
        exit 1
    fi

    local result
    result=$(probe_network)
    local code=$?

    case $code in
        0) log "网络已在线，无需登录"; exit 0 ;;
        2)
            log "检测到认证页: $result"
            do_login "$USERNAME" "$PASSWORD" "$result"
            ;;
        *) log "网络不可达"; exit 1 ;;
    esac
}

# 状态检测
cmd_status() {
    local result
    result=$(probe_network)
    local code=$?

    case $code in
        0) echo "✓ 在线" ;;
        2) echo "⚠ 需要认证: $result" ;;
        *) echo "✗ 离线" ;;
    esac
}

# 守护进程
cmd_watch() {
    if ! load_config; then
        echo "请先运行: $0 init"
        exit 1
    fi

    log "守护进程启动 (账号: $USERNAME, 间隔: ${INTERVAL}s)"
    while true; do
        local result
        result=$(probe_network)
        local code=$?
        case $code in
            0) ;;  # 在线，不打日志
            2)
                log "检测到认证页，尝试登录..."
                do_login "$USERNAME" "$PASSWORD" "$result" || true
                ;;
            *) log "网络不可达" ;;
        esac
        sleep "$INTERVAL"
    done
}

# 主入口
case "${1:-watch}" in
    init)   cmd_init ;;
    login)  cmd_login ;;
    status) cmd_status ;;
    watch)  cmd_watch ;;
    *)
        echo "用法: $0 {init|login|status|watch}"
        echo "  init    初始化配置"
        echo "  login   立即登录一次"
        echo "  status  检测当前网络状态"
        echo "  watch   后台守护进程（默认）"
        exit 1
        ;;
esac
