#!/usr/bin/env bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 1. Check OS distribution and set package manager
OS_TYPE=""
PKG_MGR=""
IS_DARWIN=0
if [ "$(uname -s)" = "Darwin" ]; then
    IS_DARWIN=1
fi

SUDO=""
if [ "$(id -u)" != "0" ]; then
    if [ "$IS_DARWIN" = "1" ]; then
        if ! command -v sudo >/dev/null 2>&1; then
            echo -e "${RED}错误: macOS 安装需要 sudo 写入服务文件。${PLAIN}"
            exit 1
        fi
        SUDO="sudo"
    else
        echo -e "${RED}错误: 必须以 root 权限运行此脚本。请使用: sudo bash $0${PLAIN}"
        exit 1
    fi
fi

if [ "$IS_DARWIN" = "1" ]; then
    PKG_MGR="brew"
else
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_TYPE=$ID
fi

case "$OS_TYPE" in
    ubuntu|debian)
        PKG_MGR="apt-get"
        export DEBIAN_FRONTEND=noninteractive
        ;;
    alpine)
        PKG_MGR="apk"
        ;;
    centos|rhel|rocky|almalinux|fedora)
        if command -v dnf >/dev/null 2>&1; then
            PKG_MGR="dnf"
        else
            PKG_MGR="yum"
        fi
        ;;
    *)
        echo -e "${RED}错误: 不支持的操作系统 ($OS_TYPE)！目前仅支持 Ubuntu/Debian/Alpine/CentOS/RHEL/Rocky/AlmaLinux/Fedora。${PLAIN}"
        exit 1
        ;;
esac
fi

echo -e "${BLUE}==========================================================${PLAIN}"
echo -e "${BLUE}        欢迎使用 GateWayVPN 一键源码部署与管理脚本${PLAIN}"
echo -e "${BLUE}==========================================================${PLAIN}"

# 3. Configure GitHub Repository URL
# Default to the official repository (jiema123/gatewayvpn)
DEFAULT_USER="jiema123"
DEFAULT_REPO="gatewayvpn"

# Allow custom repository override via command line arguments
GITHUB_USER="${1:-${DEFAULT_USER}}"
GITHUB_REPO="${2:-${DEFAULT_REPO}}"
ARG_DEPLOY_BRANCH="${3:-}"

GITHUB_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git"
GITHUB_ARCHIVE_URL=""
GITHUB_RELEASE_PACKAGE_URL=""
BREW_RUNNER=""
if [ "$IS_DARWIN" = "1" ] && [ "$(id -u)" = "0" ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    BREW_RUNNER="sudo -u ${SUDO_USER}"
fi

echo -e "\n${YELLOW}[1/4] 正在安装系统基础依赖...${PLAIN}"
if [ "$PKG_MGR" = "brew" ]; then
    if ! command -v brew >/dev/null 2>&1; then
        echo -e "${RED}错误: macOS 环境需要先安装 Homebrew。${PLAIN}"
        exit 1
    fi
    echo -e "  -> 正在使用 Homebrew 安装依赖..."
    ${BREW_RUNNER} brew install openvpn curl python3
elif [ "$PKG_MGR" = "apt-get" ]; then
    echo -e "  -> 正在运行 apt-get update 更新软件源清单..."
    apt-get update -q || true
    echo -e "  -> 正在运行 apt-get install 安装基础依赖包..."
    apt-get install -y openvpn curl ca-certificates iptables iproute2 psmisc python3
elif [ "$PKG_MGR" = "apk" ]; then
    echo -e "  -> 正在运行 apk update 更新软件源清单..."
    apk update || true
    echo -e "  -> 正在运行 apk add 安装基础依赖包..."
    # bash is required for this script itself and some internal logic
    apk add openvpn curl ca-certificates iptables iproute2 psmisc python3 bash
elif [ "$PKG_MGR" = "dnf" ] || [ "$PKG_MGR" = "yum" ]; then
    echo -e "  -> 正在运行 $PKG_MGR 安装基础依赖包..."
    if [ "$OS_TYPE" != "fedora" ]; then
        echo -e "     -> 正在安装 EPEL 软件源 (以支持 openvpn)..."
        $PKG_MGR install -y epel-release || true
    fi
    # Try installing packages. Note: iproute or iproute2
    $PKG_MGR install -y openvpn curl ca-certificates iptables iproute psmisc python3 || \
    $PKG_MGR install -y openvpn curl ca-certificates iptables iproute2 psmisc python3
fi

# 4. Install source package
INSTALL_DIR="/opt/gatewayvpn"
if [ "$PKG_MGR" = "brew" ]; then
    INSTALL_USER="${SUDO_USER:-$(id -un)}"
    INSTALL_HOME="$(eval echo "~${INSTALL_USER}")"
    INSTALL_DIR="${INSTALL_HOME}/gatewayvpn"
fi
APP_BIN="${INSTALL_DIR}/bin/gatewayvpn-manager"
ML_BIN="/usr/bin/ml"
PYTHON_BIN="/usr/bin/python3"
OPENVPN_BIN="$(command -v openvpn || true)"
SERVICE_KIND="manual"
LAUNCHD_PLIST="/Library/LaunchDaemons/com.gatewayvpn.manager.plist"
if [ "$IS_DARWIN" = "1" ]; then
    ML_BIN="/usr/local/bin/ml"
    PYTHON_BIN="$(command -v python3 || true)"
    if [ -z "$PYTHON_BIN" ]; then
        PYTHON_BIN="/opt/homebrew/bin/python3"
    fi
    if [ -z "$OPENVPN_BIN" ]; then
        for candidate in /usr/local/sbin/openvpn /opt/homebrew/sbin/openvpn /usr/sbin/openvpn; do
            if [ -x "$candidate" ]; then
                OPENVPN_BIN="$candidate"
                break
            fi
        done
    fi
    SERVICE_KIND="launchd"
fi
if [ -z "$OPENVPN_BIN" ]; then
    OPENVPN_BIN="openvpn"
fi
# 默认部署分支（在 bate 分支设为 bate；在 main 分支设为 main）
DEFAULT_DEPLOY_BRANCH="${ARG_DEPLOY_BRANCH:-${GATEWAYVPN_BRANCH:-main}}"

DEPLOY_BRANCH="${DEFAULT_DEPLOY_BRANCH}"
GITHUB_ARCHIVE_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${DEPLOY_BRANCH}.tar.gz"

UNAME_S="$(uname -s)"
UNAME_M="$(uname -m)"
case "$UNAME_S" in
    Darwin) RELEASE_OS="darwin" ;;
    Linux) RELEASE_OS="linux" ;;
    *) RELEASE_OS="$(printf '%s' "$UNAME_S" | tr '[:upper:]' '[:lower:]')" ;;
esac
case "$UNAME_M" in
    x86_64|amd64) RELEASE_ARCH="x86_64" ;;
    arm64|aarch64) RELEASE_ARCH="arm64" ;;
    *) RELEASE_ARCH="$UNAME_M" ;;
esac
RELEASE_PACKAGE_NAME="gatewayvpn-${DEPLOY_BRANCH}-${RELEASE_OS}-${RELEASE_ARCH}.tar.gz"
GITHUB_RELEASE_PACKAGE_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/${DEPLOY_BRANCH}/${RELEASE_PACKAGE_NAME}"

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

SOURCE_DIR=""
if [ "${GATEWAYVPN_FORCE_REMOTE:-0}" != "1" ] && [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/vpngate_manager.py" ] && [ -f "${SCRIPT_DIR}/vpn_utils.py" ]; then
    SOURCE_DIR="$SCRIPT_DIR"
fi

copy_source_to_install_dir() {
    src="$1"
    dst="$2"
    if [ "$src" = "$dst" ]; then
        echo -e "  -> 安装源与目标目录相同，跳过复制。"
        return 0
    fi
    ${SUDO} mkdir -p "$dst" "$dst/vpngate_data"
    if command -v rsync >/dev/null 2>&1; then
        ${SUDO} rsync -a --delete \
            --exclude ".git" \
            --exclude ".local_dev" \
            --exclude "vpngate_data/" \
            --filter "protect vpngate_data/***" \
            --exclude "__pycache__" \
            "$src"/ "$dst"/
    else
        tmp_copy_dir="$(mktemp -d)"
        (cd "$src" && tar --exclude ".git" --exclude ".local_dev" --exclude "vpngate_data" --exclude "__pycache__" -cf - .) | (cd "$tmp_copy_dir" && tar -xf -)
        ${SUDO} cp -R "$tmp_copy_dir"/. "$dst"/
        rm -rf "$tmp_copy_dir"
    fi
}

build_app_binary() {
    src_dir="$1"
    if [ ! -x "${src_dir}/scripts/build-binary.sh" ]; then
        if [ ! -f "${src_dir}/scripts/build-binary.sh" ]; then
            echo -e "${RED}  -> 错误: 未找到打包脚本 scripts/build-binary.sh${PLAIN}"
            return 1
        fi
        chmod +x "${src_dir}/scripts/build-binary.sh"
    fi
    echo -e "  -> 正在构建可执行应用..."
    if ! (cd "$src_dir" && bash ./scripts/build-binary.sh); then
        echo -e "${RED}  -> 错误: 可执行应用构建失败，请检查本机 Python 打包环境。${PLAIN}"
        return 1
    fi
}

compute_expected_build_id() {
    src_dir="$1"
    (
        cd "$src_dir"
        shasum app_runtime.py vpngate_manager.py vpn_utils.py proxy_server.py scripts/build-binary.sh
    ) | shasum | awk '{print $1}'
}

ensure_fresh_binary() {
    src_dir="$1"
    expected_build_id="$(compute_expected_build_id "$src_dir")"
    current_build_id=""
    if [ -f "${src_dir}/bin/gatewayvpn-manager.build-id" ]; then
        current_build_id="$(tr -d '[:space:]' < "${src_dir}/bin/gatewayvpn-manager.build-id")"
    fi
    if [ ! -x "${src_dir}/bin/gatewayvpn-manager" ] || [ "$current_build_id" != "$expected_build_id" ]; then
        build_app_binary "$src_dir"
    fi
}

download_and_extract_package() {
    package_url="$1"
    target_archive="$2"
    target_dir="$3"
    if ! curl -L --fail --retry 3 -o "$target_archive" "$package_url"; then
        return 1
    fi
    tar -xzf "$target_archive" -C "$target_dir"
    return 0
}

echo -e "\n${YELLOW}[2/4] 正在部署 GateWayVPN 到 ${INSTALL_DIR} (目标分支: ${DEPLOY_BRANCH})...${PLAIN}"
if [ "$IS_DARWIN" = "1" ]; then
    if [ ! -d "${INSTALL_DIR}" ]; then
        mkdir -p "${INSTALL_DIR}"
    fi
fi
if [ -n "$SOURCE_DIR" ]; then
    echo -e "  -> 检测到本地部署包，正在从 ${SOURCE_DIR} 安装..."
    ensure_fresh_binary "$SOURCE_DIR"
    copy_source_to_install_dir "$SOURCE_DIR" "$INSTALL_DIR"
else
    echo -e "  -> 未检测到本地部署包，优先下载 GitHub Release 预构建资产 ${RELEASE_PACKAGE_NAME} ..."
    TMP_DIR="$(mktemp -d)"
    ARCHIVE_FILE="${TMP_DIR}/gatewayvpn.tar.gz"
    if download_and_extract_package "$GITHUB_RELEASE_PACKAGE_URL" "$ARCHIVE_FILE" "$TMP_DIR"; then
        echo -e "${GREEN}  -> 已下载 Release 预构建资产。${PLAIN}"
    else
        echo -e "${YELLOW}  -> 未找到对应 Release 资产，回退到源码包并在本机构建二进制...${PLAIN}"
        rm -f "$ARCHIVE_FILE"
        if ! download_and_extract_package "$GITHUB_ARCHIVE_URL" "$ARCHIVE_FILE" "$TMP_DIR"; then
            echo -e "${RED}  -> 错误: 无法下载 Release 资产或源码包，请检查网络、分支或 Release 发布状态。${PLAIN}"
            rm -rf "$TMP_DIR"
            exit 1
        fi
    fi
    EXTRACTED_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [ -z "$EXTRACTED_DIR" ] || [ ! -f "${EXTRACTED_DIR}/install.sh" ]; then
        echo -e "${RED}  -> 错误: 部署包内容不完整。${PLAIN}"
        rm -rf "$TMP_DIR"
        exit 1
    fi
    ensure_fresh_binary "$EXTRACTED_DIR"
    copy_source_to_install_dir "$EXTRACTED_DIR" "$INSTALL_DIR"
    rm -rf "$TMP_DIR"
fi

if [ ! -x "${APP_BIN}" ]; then
    echo -e "${RED}  -> 错误: 未找到可执行应用 ${APP_BIN}${PLAIN}"
    exit 1
fi

if [ "$IS_DARWIN" = "1" ]; then
    ${SUDO} mkdir -p "${INSTALL_DIR}/vpngate_data"
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        ${SUDO} chown -R "${SUDO_USER}:staff" "${INSTALL_DIR}"
    else
        ${SUDO} chown -R "$(id -un):staff" "${INSTALL_DIR}" 2>/dev/null || true
    fi
else
    mkdir -p "${INSTALL_DIR}/vpngate_data"
fi
echo -e "${GREEN}  -> 部署包安装完成！${PLAIN}"

# 5. Configure Service
echo -e "\n${YELLOW}[3/4] 正在配置系统服务...${PLAIN}"
if [ "$IS_DARWIN" = "1" ]; then
    echo -e "  -> 检测到 macOS，正在创建 launchd 服务配置 ${LAUNCHD_PLIST} ..."
    ${SUDO} mkdir -p /Library/LaunchDaemons "${INSTALL_DIR}/vpngate_data"
    ${SUDO} tee "${LAUNCHD_PLIST}" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.gatewayvpn.manager</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_BIN}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${INSTALL_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${INSTALL_DIR}/vpngate_data/launchd.out.log</string>
    <key>StandardErrorPath</key>
    <string>${INSTALL_DIR}/vpngate_data/launchd.err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/sbin:/usr/sbin</string>
        <key>OPENVPN_CMD</key>
        <string>${OPENVPN_BIN}</string>
    </dict>
</dict>
</plist>
EOF
    ${SUDO} chown root:wheel "${LAUNCHD_PLIST}"
    ${SUDO} chmod 644 "${LAUNCHD_PLIST}"
elif command -v systemctl >/dev/null 2>&1; then
    echo -e "  -> 检测到 systemd，正在创建服务配置 /lib/systemd/system/gatewayvpn.service ..."
    cat > /lib/systemd/system/gatewayvpn.service <<EOF
[Unit]
Description=GateWayVPN OpenVPN Manager with HTTP/SOCKS5 Proxy
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${APP_BIN}
Restart=always
RestartSec=5
Environment=OPENVPN_CMD=${OPENVPN_BIN}
EnvironmentFile=-/etc/default/gatewayvpn

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable gatewayvpn.service
    SERVICE_KIND="systemd"
elif command -v rc-service >/dev/null 2>&1; then
    echo -e "  -> 检测到 OpenRC，正在创建服务配置 /etc/init.d/gatewayvpn ..."
    cat > /etc/init.d/gatewayvpn <<EOF
#!/sbin/openrc-run

description="GateWayVPN OpenVPN Manager with HTTP/SOCKS5 Proxy"
command="${APP_BIN}"
command_background="yes"
directory="${INSTALL_DIR}"
pidfile="/run/gatewayvpn.pid"

depend() {
    need net
    after firewall
}
EOF
    chmod +x /etc/init.d/gatewayvpn
    rc-update add gatewayvpn default
    SERVICE_KIND="openrc"
else
    echo -e "${YELLOW}警告: 未能检测到 systemd 或 OpenRC，请手动管理服务。${PLAIN}"
fi

# 6. Configure global command shortcut "ml"
echo -e "\n${YELLOW}[4/4] 正在创建全局命令快捷接口 'ml'...${PLAIN}"
echo -e "  -> 正在写入管理脚本 ${ML_BIN} ..."
${SUDO} mkdir -p "$(dirname "${ML_BIN}")"
${SUDO} tee "${ML_BIN}" >/dev/null <<'EOF'
#!/usr/bin/env python3
import sys
import os
import socket
import subprocess
import time
import tty
import termios
import shutil

INSTALL_DIR = "${INSTALL_DIR}"
APP_BIN = "${APP_BIN}"
LOG_FILE = "${INSTALL_DIR}/vpngate_data/vpngate.log"
SERVICE_KIND = "${SERVICE_KIND}"
LAUNCHD_PLIST = "${LAUNCHD_PLIST}"
LAUNCHD_LABEL = "com.gatewayvpn.manager"
GITHUB_USER = "${GITHUB_USER}"
GITHUB_REPO = "${GITHUB_REPO}"
DEPLOY_BRANCH = "${DEPLOY_BRANCH}"
UPDATE_ARCHIVE_URL = "${GITHUB_ARCHIVE_URL}"

def generate_random_password():
    import random
    import string
    chars = string.ascii_letters + string.digits
    while True:
        pwd = "".join(random.choices(chars, k=12))
        if any(c.islower() for c in pwd) and any(c.isupper() for c in pwd) and any(c.isdigit() for c in pwd):
            return pwd

def generate_random_suffix():
    import random
    import string
    return "".join(random.choices(string.ascii_letters + string.digits, k=12))

def load_ui_cfg():
    import json
    path = os.path.join(INSTALL_DIR, "vpngate_data", "ui_auth.json")
    cfg = {"host": "::", "port": 8787, "secret_path": "EJsW2EeBo9lY", "password": ""}
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
                for k, v in data.items():
                    cfg[k] = v
        except Exception:
            pass
    return cfg

def save_ui_cfg(cfg):
    import json
    path = os.path.join(INSTALL_DIR, "vpngate_data", "ui_auth.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
        return True
    except Exception:
        return False

def load_state():
    import json
    path = os.path.join(INSTALL_DIR, "vpngate_data", "state.json")
    state = {"active_openvpn_node_id": "", "last_check_message": "", "is_connecting": False}
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
                for k, v in data.items():
                    state[k] = v
        except Exception:
            pass
    return state

def get_active_node_info():
    import json
    path = os.path.join(INSTALL_DIR, "vpngate_data", "nodes.json")
    state = load_state()
    active_id = state.get("active_openvpn_node_id")
    if not active_id:
        return None, None
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                nodes = json.load(f)
                for n in nodes:
                    if n.get("id") == active_id:
                        ip = n.get("ip") or n.get("remote_host")
                        loc = n.get("location") or n.get("country") or "未知"
                        return ip, loc
        except Exception:
            pass
    return None, None

def ping_ip(ip):
    if not ip:
        return None
    try:
        # Run standard linux ping command with 1 packet and 2 seconds timeout
        res = subprocess.run(["ping", "-c", "1", "-W", "2", ip], capture_output=True, text=True, timeout=3)
        if res.returncode == 0:
            out = res.stdout
            lines = out.splitlines()
            for line in lines:
                if "rtt" in line or "min/avg" in line:
                    parts = line.split("=")[1].strip().split("/")
                    if len(parts) >= 2:
                        avg_rtt = float(parts[1])
                        return f"{int(avg_rtt)} ms"
            return "已响应"
        else:
            return "检测超时"
    except Exception:
        return "无法连接"

def get_public_ip():
    path = os.path.join(INSTALL_DIR, "vpngate_data", "public_ip.txt")
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                ip = f.read().strip()
                if ip:
                    return ip
        except Exception:
            pass
    import urllib.request
    # Try dual-stack first, then IPv6-only, then IPv4-only
    for api_url in ["https://api64.ipify.org", "https://api6.ipify.org", "https://api.ipify.org"]:
        try:
            req = urllib.request.Request(api_url, headers={"User-Agent": "curl/7.68.0"})
            with urllib.request.urlopen(req, timeout=2) as r:
                ip = r.read().decode().strip()
                if ip:
                    try:
                        os.makedirs(os.path.dirname(path), exist_ok=True)
                        with open(path, "w", encoding="utf-8") as f:
                            f.write(ip)
                    except Exception:
                        pass
                    return ip
        except Exception:
            pass
    return "您的服务器公网IP"

def check_port_listening(port):
    for host, family in [("127.0.0.1", socket.AF_INET), ("::1", socket.AF_INET6)]:
        try:
            s = socket.socket(family, socket.SOCK_STREAM)
            s.settimeout(0.2)
            s.connect((host, port))
            s.close()
            return True
        except Exception:
            pass
    return False

def get_service_pid(service_name="gatewayvpn.service"):
    if SERVICE_KIND == "launchd":
        try:
            res = subprocess.run(["pgrep", "-f", APP_BIN], capture_output=True, text=True)
            for line in res.stdout.splitlines():
                pid = line.strip()
                if pid:
                    return pid
        except Exception:
            pass
        return None
    try:
        for pid_dir in os.listdir('/proc'):
            if pid_dir.isdigit():
                try:
                    with open(os.path.join('/proc', pid_dir, 'cmdline'), 'r') as f:
                        cmd = f.read()
                        if APP_BIN in cmd or 'gatewayvpn-manager' in cmd:
                            return pid_dir
                except Exception:
                    continue
    except Exception:
        pass
    return None

def check_service_active(service_name="gatewayvpn.service"):
    return get_service_pid(service_name) is not None

def check_openvpn_process():
    if SERVICE_KIND == "launchd":
        try:
            res = subprocess.run(["pgrep", "-x", "openvpn"], capture_output=True, text=True)
            return res.returncode == 0 and bool(res.stdout.strip())
        except Exception:
            return False
    try:
        for pid_dir in os.listdir('/proc'):
            if pid_dir.isdigit():
                try:
                    with open(os.path.join('/proc', pid_dir, 'cmdline'), 'r') as f:
                        cmd = f.read().split('\x00')[0]
                        if 'openvpn' in cmd:
                            return True
                except Exception:
                    continue
    except Exception:
        pass
    return False

def get_display_width(s):
    import re
    ansi_escape = re.compile(r'\x1b\[[0-9;]*[mGKH]')
    s_clean = ansi_escape.sub('', s)
    width = 0
    for char in s_clean:
        if ord(char) > 127:
            width += 2
        else:
            width += 1
    return width

def format_line(label, value, target_width=26):
    prefix = "  ● "
    w = get_display_width(label)
    padding = " " * max(0, target_width - w)
    return f"{prefix}{label}{padding}:  {value}"

def print_line(text=""):
    print(f"{text}\033[K")

def print_status():
    cfg = load_ui_cfg()
    ui_port = cfg.get("port", 8787)
    secret_path = cfg.get("secret_path", "EJsW2EeBo9lY")
    proxy_port = cfg.get("proxy_port", 7928)
    state = load_state()
    is_connecting = state.get("is_connecting", False)
    
    gateway_ok = check_port_listening(proxy_port)
    ui_ok = check_port_listening(ui_port)
    service_ok = check_service_active("gatewayvpn.service")
    openvpn_ok = check_openvpn_process()
    pid = get_service_pid("gatewayvpn.service")
    
    active_ip, active_loc = get_active_node_info()
    latency = state.get("active_node_latency", "测试中...") if active_ip else "无活动连接"
    
    green = "\033[1;32m"
    red = "\033[1;31m"
    reset = "\033[0m"
    bold = "\033[1m"
    yellow = "\033[1;33m"
    
    backend_status = f"{green}[已激活] (PID: {pid}){reset}" if (service_ok and pid) else f"{red}[未启动]{reset}"
    ui_status = f"{green}[已激活]{reset}" if ui_ok else f"{red}[未启动]{reset}"
    
    if is_connecting:
        gateway_status = f"{yellow}[切换中...]{reset}"
        openvpn_status = f"{yellow}[{state.get('active_node_latency') or '连接中'}...]{reset}"
    else:
        gateway_status = f"{green}[已激活]{reset}" if gateway_ok else f"{red}[未启动]{reset}"
        openvpn_status = f"{green}[已连接]{reset}" if openvpn_ok else f"{red}[未连接]{reset}"
    
    print_line("=======================================================")
    print_line(f"               {bold}GateWayVPN 管理终端 v2.0{reset}                  ")
    print_line("=======================================================")
    print_line("【核心服务状态】")
    print_line(format_line(f"代理网关 (Port {proxy_port})", gateway_status))
    print_line(format_line("服务进程", backend_status))
    print_line(format_line(f"管理后台 (Port {ui_port})", ui_status))
    print_line(format_line("连接核心 (OpenVPN)", openvpn_status))
    
    host_cfg = cfg.get("host", "::")
    if host_cfg in ("127.0.0.1", "localhost"):
        login_ip = "127.0.0.1"
    elif host_cfg == "::1":
        login_ip = "[::1]"
    elif host_cfg == "::":
        login_ip = get_public_ip()
    else:
        login_ip = f"[{host_cfg}]" if ":" in host_cfg else host_cfg
    print_line(format_line("网页登录地址", f"{yellow}http://{login_ip}:{ui_port}/{secret_path}/{reset}"))
    print_line(format_line("网页管理账号", cfg.get("username", "未配置")))
    curr_pwd = cfg.get("password", "")
    masked_pwd = curr_pwd if len(curr_pwd) <= 4 else curr_pwd[:3] + "********" + curr_pwd[-2:]
    print_line(format_line("网页管理密码", masked_pwd))
    print_line()
    print_line("【活动节点状态】")
    if is_connecting:
        connecting_msg = state.get('last_check_message') or '正在建立加密隧道并验证路由规则...'
        print_line(format_line("节点状态", f"{yellow}{connecting_msg}{reset}"))
    elif active_ip:
        proxy_ip = state.get("proxy_ip", "-")
        proxy_latency = state.get("proxy_latency_ms", 0)
        proxy_ok = state.get("proxy_ok", False)
        
        print_line(format_line("节点 IP (入口)", active_ip))
        print_line(format_line("节点地区", active_loc))
        print_line(format_line("节点延迟 (直连测试)", latency))
        if proxy_ok and proxy_ip and proxy_ip != "-":
            print_line(format_line("出口 IP (出站)", proxy_ip))
            print_line(format_line("本地代理延迟", f"{proxy_latency} ms" if proxy_latency else "检测中..."))
        else:
            proxy_err = state.get("proxy_error") or "检测中/未就绪"
            print_line(format_line("出口 IP (出站)", f"{red}[不可用 - {proxy_err}]{reset}"))
    else:
        print_line(format_line("节点状态", "无活动连接"))
    print_line()
    local_proxy = state.get("local_proxy", f"http://127.0.0.1:{proxy_port}")
    import urllib.parse
    try:
        parsed = urllib.parse.urlsplit(local_proxy)
        proxy_host = parsed.hostname or "127.0.0.1"
        proxy_port = parsed.port or proxy_port
    except Exception:
        proxy_host = "127.0.0.1"
        proxy_port = proxy_port
    
    if proxy_host == "::":
        socks_addr = "127.0.0.1"
    elif ":" in proxy_host:
        socks_addr = f"[{proxy_host}]"
    else:
        socks_addr = proxy_host

    print_line("【使用方法】")
    print_line(f"  export http_proxy=socks5://{socks_addr}:{proxy_port}")
    print_line(f"  export https_proxy=socks5://{socks_addr}:{proxy_port}")
    print_line("=======================================================")

def run_service_cmd(cmd):
    if SERVICE_KIND == "launchd":
        prefix = []
        if os.geteuid() != 0 and shutil.which("sudo"):
            prefix = ["sudo"]
        if cmd in ("stop", "restart"):
            subprocess.run(prefix + ["launchctl", "bootout", "system", LAUNCHD_PLIST], stderr=subprocess.DEVNULL)
        if cmd in ("start", "restart"):
            subprocess.run(prefix + ["launchctl", "bootstrap", "system", LAUNCHD_PLIST])
            subprocess.run(prefix + ["launchctl", "enable", f"system/{LAUNCHD_LABEL}"], stderr=subprocess.DEVNULL)
            subprocess.run(prefix + ["launchctl", "kickstart", "-k", f"system/{LAUNCHD_LABEL}"], stderr=subprocess.DEVNULL)
    elif shutil.which("systemctl"):
        subprocess.run(["systemctl", cmd, "gatewayvpn.service"])
    elif shutil.which("rc-service"):
        subprocess.run(["rc-service", "gatewayvpn", cmd])
    else:
        print("未检测到支持的服务管理器 (launchd/systemd/OpenRC)")

def start_service():
    print("正在启动 GateWayVPN 服务...", flush=True)
    run_service_cmd("start")
    print("已发送启动指令。")
    time.sleep(1)

def stop_service():
    print("正在停止 GateWayVPN 服务...", flush=True)
    run_service_cmd("stop")
    print("已发送停止指令。")
    time.sleep(1)

def restart_service():
    print("正在重启 GateWayVPN 服务...", flush=True)
    run_service_cmd("restart")
    print("已发送重启指令。")
    time.sleep(1)

def show_logs():
    print("正在查看 GateWayVPN 日志 (按 Ctrl+C 退出)...", flush=True)
    if os.path.exists(LOG_FILE):
        try:
            subprocess.run(["tail", "-f", "-n", "50", LOG_FILE])
        except KeyboardInterrupt:
            pass
    else:
        print(f"日志文件不存在: {LOG_FILE}")
        time.sleep(2)

def update_service():
    print("正在下载远程部署包并更新...", flush=True)
    confirm = input(f"将从 {GITHUB_USER}/{GITHUB_REPO}:{DEPLOY_BRANCH} 下载部署包并覆盖程序文件，保留 vpngate_data。是否继续？(Y/n): ").strip().lower()
    if confirm not in ('', 'y', 'yes'):
        print("已取消更新。")
        time.sleep(1.5)
        return
    import tempfile
    import tarfile
    import urllib.request
    try:
        with tempfile.TemporaryDirectory() as tmp:
            archive_path = os.path.join(tmp, "gatewayvpn.tar.gz")
            print(f"正在下载: {UPDATE_ARCHIVE_URL}", flush=True)
            req = urllib.request.Request(UPDATE_ARCHIVE_URL, headers={"User-Agent": "gatewayvpn-updater"})
            with urllib.request.urlopen(req, timeout=30) as response, open(archive_path, "wb") as f:
                shutil.copyfileobj(response, f)
            with tarfile.open(archive_path, "r:gz") as tar:
                tar.extractall(tmp)
            candidates = [
                os.path.join(tmp, name)
                for name in os.listdir(tmp)
                if os.path.isdir(os.path.join(tmp, name))
            ]
            source_dir = next((p for p in candidates if os.path.exists(os.path.join(p, "install.sh"))), "")
            if not source_dir:
                raise RuntimeError("部署包中未找到 install.sh")
            print("部署包下载完成，正在重新运行安装脚本...", flush=True)
            env = os.environ.copy()
            env["GATEWAYVPN_BRANCH"] = DEPLOY_BRANCH
            subprocess.run(["bash", os.path.join(source_dir, "install.sh"), GITHUB_USER, GITHUB_REPO], check=True, env=env)
            print("更新已完成！")
            time.sleep(2)
    except Exception as e:
        print(f"更新失败: {e}")
        time.sleep(4)

def uninstall_service():
    confirm = input("确定要完全卸载 GateWayVPN 吗？(y/N): ")
    if confirm.lower() == 'y':
        print("正在完全卸载 GateWayVPN...", flush=True)
        stop_service()
        if shutil.which("systemctl"):
            subprocess.run(["systemctl", "disable", "gatewayvpn.service"])
            try:
                os.unlink("/lib/systemd/system/gatewayvpn.service")
            except Exception:
                pass
        elif shutil.which("rc-service"):
            subprocess.run(["rc-update", "del", "gatewayvpn"])
            try:
                os.unlink("/etc/init.d/gatewayvpn")
            except Exception:
                pass
        elif SERVICE_KIND == "launchd":
            subprocess.run(["launchctl", "bootout", "system", LAUNCHD_PLIST], stderr=subprocess.DEVNULL)
            try:
                os.unlink(LAUNCHD_PLIST)
            except Exception:
                pass
        try:
            os.unlink("${ML_BIN}")
        except Exception:
            pass
        subprocess.run(["rm", "-rf", INSTALL_DIR])
        print("GateWayVPN 已卸载！")
        sys.exit(0)
    else:
        print("已取消卸载。")
        time.sleep(1)

def ask_restart():
    ans = input("配置已保存。是否立即重启服务生效？(Y/n): ").strip().lower()
    if ans in ('', 'y', 'yes'):
        print("正在重启 GateWayVPN 服务...", flush=True)
        restart_service()
        print("服务已重启。")
        time.sleep(1.5)

def configure_web():
    cfg = load_ui_cfg()
    while True:
        print("\033[H\033[J", end="")
        print("=======================================================")
        print("               网页绑定与地址后缀配置                  ")
        print("=======================================================")
        print(f"  [1] 切换绑定地址 (当前: {cfg.get('host', '0.0.0.0')})")
        print(f"  [2] 随机重置安全后缀 (当前: {cfg.get('secret_path', '')})")
        print("  [3] 返回主菜单")
        print("=======================================================")
        print("请直接输入数字键 [1-3] 快速执行：", end="", flush=True)
        
        key = getch()
        if key == '1':
            print("\033[H\033[J", end="")
            print("选择网页登录绑定地址：")
            print("  1. 仅允许本地 IPv4 登录 (127.0.0.1 - 更安全)")
            print("  2. 允许 IPv4 公网登录 (0.0.0.0)")
            print("  3. 允许 IPv4 & IPv6 双栈公网登录 (:: - 推荐)")
            print("  4. 仅允许本地 IPv6 登录 (::1)")
            sel = input("请选择 (1/2/3/4, 默认3): ").strip()
            if sel == '1':
                cfg['host'] = "127.0.0.1"
            elif sel == '2':
                cfg['host'] = "0.0.0.0"
            elif sel == '4':
                cfg['host'] = "::1"
            else:
                cfg['host'] = "::"
            save_ui_cfg(cfg)
            print(f"绑定地址已更新为: {cfg['host']}")
            ask_restart()
            break
        elif key == '2':
            print("\033[H\033[J", end="")
            new_path = generate_random_suffix()
            cfg['secret_path'] = new_path
            save_ui_cfg(cfg)
            print("安全登录后缀已随机重置成功！")
            print(f"您的全新安全登录后缀为: {new_path}")
            display_host = cfg['host']
            if ":" in display_host:
                display_host = f"[{display_host}]"
            print(f"新的访问路径为: http://{display_host}:{cfg['port']}/{new_path}/")
            ask_restart()
            break
        elif key == '3' or key == 'q' or key == '\x03':
            break

def configure_port():
    cfg = load_ui_cfg()
    while True:
        print("\033[H\033[J", end="")
        print("=======================================================")
        print("                      端口配置菜单                     ")
        print("=======================================================")
        print(f"1) 网页管理端口: {cfg.get('port', 8787)}")
        print(f"2) 代理出站端口: {cfg.get('proxy_port', 7928)}")
        print("3) 返回主菜单")
        print("-------------------------------------------------------")
        key = input("请选择操作 (1-3): ").strip()
        if key == '1':
            try:
                val = input("请输入新的网页管理端口 (1-65535, 按回车取消): ").strip()
                if val:
                    port = int(val)
                    if 1 <= port <= 65535:
                        cfg['port'] = port
                        save_ui_cfg(cfg)
                        print(f"网页管理端口已更新为: {port}")
                        ask_restart()
                    else:
                        print("错误: 端口范围必须在 1 至 65535 之间。")
                        time.sleep(2)
            except ValueError:
                print("错误: 输入必须是数字。")
                time.sleep(2)
        elif key == '2':
            try:
                val = input("请输入新的代理出站端口 (1024-65535, 按回车取消): ").strip()
                if val:
                    port = int(val)
                    if 1024 <= port <= 65535:
                        cfg['proxy_port'] = port
                        save_ui_cfg(cfg)
                        print(f"代理出站端口已更新为: {port}")
                        ask_restart()
                    else:
                        print("错误: 端口范围必须在 1024 至 65535 之间。")
                        time.sleep(2)
            except ValueError:
                print("错误: 输入必须是数字。")
                time.sleep(2)
        elif key == '3' or key == 'q' or key == '\x03':
            break

def configure_credentials():
    cfg = load_ui_cfg()
    while True:
        print("\033[H\033[J", end="")
        print("=======================================================")
        print("                    管理账号密码管理                   ")
        print("=======================================================")
        curr_uname = cfg.get('username', '未配置')
        curr_pwd = cfg.get('password', '')
        masked_pwd = curr_pwd if len(curr_pwd) <= 4 else curr_pwd[:3] + "********" + curr_pwd[-2:]
        print(f"当前管理账号: {curr_uname}")
        print(f"当前管理密码: {masked_pwd}")
        print("  [1] 自定义修改账号密码")
        print("  [2] 随机重置安全密码")
        print("  [3] 返回主菜单")
        print("=======================================================")
        print("请直接输入数字键 [1-3] 快速执行：", end="", flush=True)
        
        key = getch()
        if key == '1':
            print("\033[H\033[J", end="")
            new_uname = input(f"请输入新管理账号 (回车默认 {curr_uname}): ").strip()
            if not new_uname:
                new_uname = curr_uname
            new_pwd = input("请输入新管理密码 (不能为空): ").strip()
            if not new_pwd:
                print("错误: 密码不能为空！")
                time.sleep(2)
                continue
            cfg['username'] = new_uname
            cfg['password'] = new_pwd
            save_ui_cfg(cfg)
            print("账号密码修改成功！")
            print(f"您的新管理账号: {new_uname}")
            print(f"您的新管理密码: {new_pwd}")
            input("\n按任意键返回菜单...")
        elif key == '2':
            print("\033[H\033[J", end="")
            new_pwd = generate_random_password()
            cfg['password'] = new_pwd
            save_ui_cfg(cfg)
            print("密码随机重置成功！")
            print(f"您的全新12位安全密码为: {new_pwd}")
            print("密码已保存在本地，不需要重启服务，刷新浏览器即可登录。")
            input("\n按任意键返回菜单...")
        elif key == '3' or key == 'q' or key == '\x03':
            break

def getch():
    fd = sys.stdin.fileno()
    try:
        old_settings = termios.tcgetattr(fd)
    except termios.error:
        return sys.stdin.read(1)
    try:
        tty.setraw(sys.stdin.fileno())
        ch = sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    return ch

def getch_timeout(timeout=1.0):
    import select
    fd = sys.stdin.fileno()
    try:
        old_settings = termios.tcgetattr(fd)
    except termios.error:
        try:
            r, _, _ = select.select([sys.stdin], [], [], timeout)
            if r:
                ch = sys.stdin.read(1)
                if not ch:
                    time.sleep(timeout)
                    return None
                return ch
        except Exception:
            time.sleep(timeout)
        return None
    try:
        tty.setraw(fd)
        r, _, _ = select.select([sys.stdin], [], [], timeout)
        if r:
            ch = sys.stdin.read(1)
            if not ch:
                return None
            return ch
        return None
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

def get_status_state():
    cfg = load_ui_cfg()
    state = load_state()
    proxy_port = cfg.get("proxy_port", 7928)
    return (
        cfg.get("port", 8787),
        cfg.get("secret_path", "EJsW2EeBo9lY"),
        cfg.get("username", "未配置"),
        cfg.get("password", ""),
        cfg.get("host", "0.0.0.0"),
        state.get("is_connecting", False),
        state.get("active_openvpn_node_id", ""),
        state.get("last_check_message", ""),
        state.get("active_node_latency", ""),
        state.get("proxy_ip", "-"),
        state.get("proxy_latency_ms", 0),
        state.get("proxy_ok", False),
        check_port_listening(proxy_port),
        check_service_active("gatewayvpn.service"),
        check_openvpn_process(),
        get_service_pid("gatewayvpn.service")
    )

def main():
    if os.geteuid() != 0 and SERVICE_KIND != "launchd":
        print("错误: 必须以 root 权限运行此命令。")
        sys.exit(1)
        
    if len(sys.argv) > 1:
        cmd = sys.argv[1].lower()
        if cmd == "start":
            start_service()
        elif cmd == "stop":
            stop_service()
        elif cmd == "restart":
            restart_service()
        elif cmd == "status":
            print("\033[?1049h\033[?25l\033[H\033[J", end="", flush=True)
            try:
                while True:
                    print("\033[H", end="")
                    print_status()
                    print_line("\n\033[1;33m提示: 当前为静态页面。按 [回车键/Enter] 手动刷新状态，按 [q] 或 [Ctrl+C] 退出...\033[0m")
                    print("\033[J", end="", flush=True)
                    
                    key = getch()
                    if key in ('q', 'Q', '\x03'):
                        break
                    if key in ('\r', '\n', '\x0a', '\x0d'):
                        continue
            except KeyboardInterrupt:
                pass
            finally:
                print("\033[?1049l\033[?25h", end="", flush=True)
        elif cmd == "logs":
            show_logs()
        elif cmd == "update":
            update_service()
        elif cmd == "uninstall":
            uninstall_service()
        elif cmd == "web":
            configure_web()
        elif cmd == "port":
            configure_port()
        elif cmd == "password":
            configure_credentials()
        else:
            print("未知命令。可用命令: start, stop, restart, status, logs, update, uninstall, web, port, password")
        sys.exit(0)
        
    options = {
        '1': ("启动服务 (ml start)", start_service),
        '2': ("停止服务 (ml stop)", stop_service),
        '3': ("重启服务 (ml restart)", restart_service),
        '4': ("日志监控 (ml logs)", show_logs),
        '5': ("网页配置 (ml web)", configure_web),
        '6': ("端口配置 (ml port)", configure_port),
        '7': ("账号密码 (ml password)", configure_credentials),
        '8': ("一键更新 (ml update)", update_service),
        '9': ("完全卸载 (ml uninstall)", uninstall_service),
        '0': ("退出终端", None)
    }
    
    # Enter alternate buffer and hide cursor
    print("\033[?1049h\033[?25l\033[H\033[J", end="", flush=True)
    try:
        need_redraw = True
        while True:
            if need_redraw:
                print("\033[H", end="")
                print_status()
                
                bold = "\033[1m"
                reset = "\033[0m"
                green = "\033[1;32m"
                
                print_line(f"【{bold}终端指令菜单栏{reset}】")
                for key in sorted(options.keys()):
                    if key == '0':
                        continue
                    name, _ = options[key]
                    print_line(f"  {green}[{key}]{reset} {name}")
                print_line(f"  {green}[0]{reset} {options['0'][0]}")
                print_line("=======================================================")
                print_line("提示: 当前为静态页面。按 [回车键/Enter] 手动刷新状态。")
                print("请直接输入数字键 [0-9] 快速选择执行：\033[K", end="", flush=True)
                print("\033[J", end="", flush=True)
                need_redraw = False
                
            try:
                key = getch()
            except KeyboardInterrupt:
                break
                
            if key == '\x03' or key == 'q' or key == 'Q':
                break
                
            if key == '0':
                break
                
            if key in ('\r', '\n', '\x0a', '\x0d'):
                need_redraw = True
                continue
                
            if key in options:
                name, func = options[key]
                if func is None:
                    break
                    
                # Temporarily restore normal terminal scrollback and show cursor
                print("\033[?1049l\033[?25h", end="", flush=True)
                print(f"正在执行: {name}...\n")
                
                try:
                    func()
                except Exception as e:
                    print(f"执行出错: {e}")
                    
                if func not in (start_service, stop_service, restart_service,
                                configure_web, configure_port, configure_credentials, show_logs, update_service):
                    input("\n操作已完成，按回车键返回主菜单...")
                    
                # Re-enter alternate buffer and hide cursor
                print("\033[?1049h\033[?25l\033[H\033[J", end="", flush=True)
                need_redraw = True
    finally:
        # Exit alternate buffer and show cursor on exit
        print("\033[?1049l\033[?25h", end="", flush=True)

if __name__ == "__main__":
    main()
EOF
${SUDO} "${PYTHON_BIN}" - "${ML_BIN}" "${INSTALL_DIR}" "${SERVICE_KIND}" "${LAUNCHD_PLIST}" "${ML_BIN}" "${GITHUB_USER}" "${GITHUB_REPO}" "${DEPLOY_BRANCH}" "${GITHUB_ARCHIVE_URL}" <<'PY'
import pathlib
import sys

path, install_dir, service_kind, launchd_plist, ml_bin, github_user, github_repo, deploy_branch, github_archive_url = sys.argv[1:]
target = pathlib.Path(path)
text = target.read_text(encoding="utf-8")
text = text.replace("${INSTALL_DIR}", install_dir)
text = text.replace("${SERVICE_KIND}", service_kind)
text = text.replace("${LAUNCHD_PLIST}", launchd_plist)
text = text.replace("${ML_BIN}", ml_bin)
text = text.replace("${GITHUB_USER}", github_user)
text = text.replace("${GITHUB_REPO}", github_repo)
text = text.replace("${DEPLOY_BRANCH}", deploy_branch)
text = text.replace("${GITHUB_ARCHIVE_URL}", github_archive_url)
target.write_text(text, encoding="utf-8")
PY
${SUDO} chmod +x "${ML_BIN}"

# 7. Configure Custom parameters (First-time installation check)
AUTH_FILE="${INSTALL_DIR}/vpngate_data/ui_auth.json"
${SUDO} mkdir -p "${INSTALL_DIR}/vpngate_data"
if [ "$IS_DARWIN" = "1" ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    ${SUDO} chown -R "${SUDO_USER}:staff" "${INSTALL_DIR}/vpngate_data"
fi

if [ ! -f "$AUTH_FILE" ]; then
    echo -e "\n${YELLOW}检测到是首次安装，是否需要自定义配置网页端参数（端口/安全后缀/登录账号密码）？${PLAIN}"
    read -p "是否自定义配置？[y/N]: " is_custom
    
    # Initialize defaults
    UI_PORT=8787
    # generate random secret suffix (12 chars alphanumeric)
    SECRET_PATH=$(python3 -c "import random, string; print(''.join(random.choices(string.ascii_letters + string.digits, k=12)))")
    # generate random password
    UI_PASSWORD=$(python3 -c "
import random, string
chars = string.ascii_letters + string.digits
while True:
    pwd = ''.join(random.choices(chars, k=12))
    if any(c.islower() for c in pwd) and any(c.isupper() for c in pwd) and any(c.isdigit() for c in pwd):
        print(pwd)
        break
")
    UI_USERNAME=$(python3 -c "
import random, string
chars = string.ascii_letters + string.digits
while True:
    uname = ''.join(random.choices(chars, k=12))
    if uname[0].isalpha() and any(c.islower() for c in uname) and any(c.isupper() for c in uname) and any(c.isdigit() for c in uname):
        print(uname)
        break
")

    if [[ "$is_custom" =~ ^[Yy]$ ]]; then
        # Step-by-step custom inputs
        # 1. Custom port
        while true; do
            read -p "请输入自定义管理端口 [1-65535, 默认 8787]: " input_port
            if [ -z "$input_port" ]; then
                UI_PORT=8787
                break
            fi
            if [[ "$input_port" =~ ^[0-9]+$ ]] && [ "$input_port" -ge 1 ] && [ "$input_port" -le 65535 ]; then
                UI_PORT=$input_port
                break
            else
                echo -e "${RED}输入错误: 端口必须是 1 到 65535 之间的数字！${PLAIN}"
            fi
        done
        
        # 2. Custom suffix
        while true; do
            read -p "请输入网页登录自定义安全后缀 [字母与数字组合, 默认随机]: " input_suffix
            if [ -z "$input_suffix" ]; then
                break
            fi
            if [[ "$input_suffix" =~ ^[A-Za-z0-9]+$ ]]; then
                SECRET_PATH=$input_suffix
                break
            else
                echo -e "${RED}输入错误: 后缀仅能由英文字母和数字组成！${PLAIN}"
            fi
        done
        
        # 3. Custom login username and password
        read -p "请输入登录账号 [默认 $UI_USERNAME]: " input_user
        if [ -n "$input_user" ]; then
            UI_USERNAME=$input_user
        fi
        
        while true; do
            read -p "请输入登录密码 [默认随机生成, 建议包含字母、数字与符号]: " input_pass
            if [ -z "$input_pass" ]; then
                break
            fi
            if [ ${#input_pass} -ge 4 ]; then
                UI_PASSWORD=$input_pass
                break
            else
                echo -e "${RED}输入错误: 密码长度不能少于 4 位！${PLAIN}"
            fi
        done
    fi

    # Write config JSON
    UI_PORT="$UI_PORT" SECRET_PATH="$SECRET_PATH" UI_USERNAME="$UI_USERNAME" UI_PASSWORD="$UI_PASSWORD" AUTH_FILE="$AUTH_FILE" python3 -c "
import os
import json
cfg = {
    'host': '::',
    'port': int(os.environ['UI_PORT']),
    'secret_path': os.environ['SECRET_PATH'],
    'username': os.environ['UI_USERNAME'],
    'password': os.environ['UI_PASSWORD']
}
with open(os.environ['AUTH_FILE'], 'w', encoding='utf-8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
"
fi

# 8. Start service
# 8.5 Optimize network parameters (rp_filter for policy routing)
if [ "$IS_DARWIN" = "1" ]; then
    echo -e "\n检测到 macOS，跳过 Linux rp_filter/sysctl 策略路由优化。"
else
echo -e "\n正在优化网络参数 (配置反向路径过滤 rp_filter=2 以支持策略路由)..."
if [ -d "/etc/sysctl.d" ]; then
    cat > /etc/sysctl.d/99-gatewayvpn.conf <<EOF
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
EOF
    sysctl -p /etc/sysctl.d/99-gatewayvpn.conf >/dev/null 2>&1 || true
else
    # Fallback to appending to /etc/sysctl.conf
    if ! grep -q "net.ipv4.conf.all.rp_filter" /etc/sysctl.conf; then
        echo "" >> /etc/sysctl.conf
        echo "net.ipv4.conf.all.rp_filter = 2" >> /etc/sysctl.conf
        echo "net.ipv4.conf.default.rp_filter = 2" >> /etc/sysctl.conf
    else
        sed -i 's/net.ipv4.conf.all.rp_filter\s*=\s*[0-9]/net.ipv4.conf.all.rp_filter = 2/g' /etc/sysctl.conf
        sed -i 's/net.ipv4.conf.default.rp_filter\s*=\s*[0-9]/net.ipv4.conf.default.rp_filter = 2/g' /etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1 || true
fi
# Apply to currently active interfaces dynamically
sysctl -w net.ipv4.conf.all.rp_filter=2 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.rp_filter=2 >/dev/null 2>&1 || true
if [ -d "/proc/sys/net/ipv4/conf" ]; then
    for dev_dir in /proc/sys/net/ipv4/conf/*; do
        dev_name=$(basename "$dev_dir")
        sysctl -w net.ipv4.conf.${dev_name}.rp_filter=2 >/dev/null 2>&1 || true
    done
fi
fi

echo -e "\n正在启动 GateWayVPN 服务并初始化网络..."
if [ "$IS_DARWIN" = "1" ]; then
    ${SUDO} launchctl bootout system "${LAUNCHD_PLIST}" >/dev/null 2>&1 || true
    ${SUDO} launchctl bootstrap system "${LAUNCHD_PLIST}" || true
    ${SUDO} launchctl enable "system/com.gatewayvpn.manager" >/dev/null 2>&1 || true
    ${SUDO} launchctl kickstart -k "system/com.gatewayvpn.manager" >/dev/null 2>&1 || true
elif command -v systemctl >/dev/null 2>&1; then
    systemctl restart gatewayvpn.service || true
elif command -v rc-service >/dev/null 2>&1; then
    rc-service gatewayvpn restart || true
fi

# Wait and poll for node loading and active connection
echo -e "\n正在等待 GateWayVPN 首次获取节点并建立加密通道 (此过程可能需要 5-30 秒)..."
ACTIVE_ID=""
LAST_MSG=""
for i in {1..90}; do
    if [ -f "${INSTALL_DIR}/vpngate_data/state.json" ]; then
        ACTIVE_ID=$(python3 -c "import json; print(json.load(open('${INSTALL_DIR}/vpngate_data/state.json')).get('active_openvpn_node_id', ''))" 2>/dev/null || echo "")
        IS_CONN=$(python3 -c "import json; print(json.load(open('${INSTALL_DIR}/vpngate_data/state.json')).get('is_connecting', False))" 2>/dev/null || echo "False")
        CUR_MSG=$(python3 -c "import json; print(json.load(open('${INSTALL_DIR}/vpngate_data/state.json')).get('last_check_message', ''))" 2>/dev/null || echo "")
        
        if [ "$IS_CONN" = "False" ] || [ "$IS_CONN" = "false" ]; then
            if [ -n "$ACTIVE_ID" ]; then
                echo -e "  -> ${GREEN}[已就绪]${PLAIN} 首次节点连接成功，活动节点: ${GREEN}$ACTIVE_ID${PLAIN}"
                break
            else
                if [ -n "$CUR_MSG" ] && [ "$CUR_MSG" != "$LAST_MSG" ]; then
                    echo -e "  -> 提示: ${YELLOW}${CUR_MSG}${PLAIN}"
                    LAST_MSG="$CUR_MSG"
                fi
            fi
        else
            if [ -n "$CUR_MSG" ] && [ "$CUR_MSG" != "$LAST_MSG" ]; then
                echo -e "  -> 状态: ${YELLOW}${CUR_MSG}${PLAIN}"
                LAST_MSG="$CUR_MSG"
            fi
        fi
    else
        echo -n "."
    fi
    sleep 1
done
if [ -z "$ACTIVE_ID" ]; then
    echo -e "  -> ${YELLOW}[加载超时]${PLAIN} 首次节点获取或连接超时，将在后台继续尝试..."
fi

SECRET_PATH="EJsW2EeBo9lY"
USERNAME="未配置"
PASSWORD="未配置"
UI_PORT=8787
AUTH_FILE="${INSTALL_DIR}/vpngate_data/ui_auth.json"
if [ -f "$AUTH_FILE" ]; then
    SECRET_PATH=$(python3 -c "import json; print(json.load(open('$AUTH_FILE')).get('secret_path', 'EJsW2EeBo9lY'))" 2>/dev/null || echo "EJsW2EeBo9lY")
    USERNAME=$(python3 -c "import json; print(json.load(open('$AUTH_FILE')).get('username', '未配置'))" 2>/dev/null || echo "未配置")
    PASSWORD=$(python3 -c "import json; print(json.load(open('$AUTH_FILE')).get('password', '未配置'))" 2>/dev/null || echo "未配置")
    UI_PORT=$(python3 -c "import json; print(json.load(open('$AUTH_FILE')).get('port', 8787))" 2>/dev/null || echo "8787")
fi

if [ "$IS_DARWIN" = "1" ]; then
    PUBLIC_IP="127.0.0.1"
    PUBLIC_IPV6=""
else
# Get VPS public IP
echo -e "正在获取 VPS 公网 IP..."
PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org || curl -s --max-time 3 https://ifconfig.me || curl -s --max-time 3 icanhazip.com || echo "您的服务器公网IP")
echo -n "$PUBLIC_IP" > "${INSTALL_DIR}/vpngate_data/public_ip.txt"

# Get VPS public IPv6
echo -e "正在获取 VPS 公网 IPv6..."
PUBLIC_IPV6=$(curl -6 -s --max-time 3 https://api.ipify.org || curl -6 -s --max-time 3 https://ifconfig.me || curl -6 -s --max-time 3 icanhazip.com || echo "")
fi

echo -e "\n${GREEN}==========================================================${PLAIN}"
echo -e "${GREEN}             GateWayVPN 源码一键部署已完成！${PLAIN}"
echo -e "${GREEN}==========================================================${PLAIN}"
echo -e "  * 网页控制面板:  ${BLUE}http://${PUBLIC_IP}:${UI_PORT}/${SECRET_PATH}/${PLAIN}"
if [ -n "$PUBLIC_IPV6" ]; then
    echo -e "  * 网页控制面板(IPv6):  ${BLUE}http://[${PUBLIC_IPV6}]:${UI_PORT}/${SECRET_PATH}/${PLAIN}"
fi
echo -e "  * 网页管理账号:  ${YELLOW}${USERNAME}${PLAIN}"
echo -e "  * 网页管理密码:  ${YELLOW}${PASSWORD}${PLAIN}"
echo -e "  * HTTP/SOCKS5 代理端口:  ${BLUE}http://127.0.0.1:7928/${PLAIN}  或  ${BLUE}http://[::1]:7928/${PLAIN}"
echo -e " --------------------------------------------------------"
echo -e "  * 快速状态指令:   ${YELLOW}ml status${PLAIN}  或  ${YELLOW}ml${PLAIN}"
echo -e "  * 查看实时日志:   ${YELLOW}ml logs${PLAIN}"
echo -e "  * 停止服务:       ${YELLOW}ml stop${PLAIN}"
echo -e "  * 重启服务:       ${YELLOW}ml restart${PLAIN}"
echo -e "=========================================================="
echo
